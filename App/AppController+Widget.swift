import AppKit
import Carbon.HIToolbox
import Combine
import ServiceManagement
import SwiftUI

/// The floating widget: placement, snapping, tucking, hit-testing and the cord.
extension AppController {
    func makeHandleWindow(frame: NSRect) -> HandleWindow {
        let window = HandleWindow(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        configure(window)
        window.hasShadow = false
        // Without this, macOS lets clicks fall through wherever the window's pixels read as transparent.
        window.ignoresMouseEvents = false
        return window
    }

    /// Puts the widget back where it last was on the best available display.
    func widgetFrame() -> NSRect {
        let prototype = debug.prototype
        let screen = PlacementStore.preferredScreen(for: prototype)
        var placement = PlacementStore.load(prototype: prototype, on: screen) ?? .standard(for: prototype)
        if CommandLine.arguments.contains("--preview-left") { placement.onLeftEdge = true }
        debug.onLeftEdge = placement.onLeftEdge
        return placement.frame(for: prototype, on: screen.visibleFrame)
    }

    @objc func screensChanged() {
        handle.setFrame(widgetFrame(), display: true)
    }

    /// Snaps to the nearest edge with a soft overshoot, then remembers the spot.
    func finishDrag() {
        lastActivity = Date()
        let prototype = debug.prototype
        let screen = handle.screen ?? NSScreen.screens[0]
        let placement = WidgetPlacement.nearest(to: handle.frame, prototype: prototype, on: screen.visibleFrame)
        PlacementStore.save(placement, prototype: prototype, on: screen)
        debug.onLeftEdge = placement.onLeftEdge
        let target = placement.frame(for: prototype, on: screen.visibleFrame)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            handle.setFrame(target, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.32
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 1.25, 0.5, 1)
            handle.animator().setFrame(target, display: true)
        }
    }

    func idleTick() {
        if let until = hiddenUntil, Date() >= until { showWidgetNow() }
        guard !debug.tucked, !presentation.presented, NSEvent.pressedMouseButtons == 0,
              UserDefaults.standard.object(forKey: "autoTuck") as? Bool ?? true,
              !isPointerNearWidget(), Date().timeIntervalSince(lastActivity) >= Self.idleSecondsBeforeTuck else { return }
        debug.tucked = true
    }

    func isPointerNearWidget() -> Bool {
        var zone = handle.frame
        if debug.prototype == .cord {
            zone = NSRect(x: zone.midX - 40, y: zone.maxY - 170, width: 80, height: 170)
        }
        return zone.insetBy(dx: -48, dy: -48).contains(NSEvent.mouseLocation)
    }

    func buildWidget() {
        handle = makeHandleWindow(frame: widgetFrame())
        let hosting = HandleHostingView(rootView: WidgetView(debug: debug, store: store))
        hosting.onClick = { [weak self] in
            guard let self else { return }
            if self.debug.prototype == .cord { self.debug.cord.nudge() } else { self.togglePanel() }
        }
        hosting.isPullMode = { [weak self] in self?.debug.prototype == .cord }
        hosting.onPull = { [weak self] dx, dy in self?.debug.cord.pull(dx: dx, dy: dy) }
        hosting.onPullEnd = { [weak self] in
            guard let self, self.debug.cord.release() else { return }
            self.togglePanel()
        }
        hosting.onSlide = { [weak self] left in self?.slideCord(toLeft: left) }
        hosting.onDragEnd = { [weak self] in self?.finishDrag() }
        hosting.onRightClick = { [weak self] event, view in self?.showRightClickMenu(event: event, view: view) }
        handle.contentView = hosting
        handle.acceptsMouseMovedEvents = true
        installCordHitTesting()
        handle.orderFrontRegardless()
        if let pull = options.previewPull {
            debug.cord.configure()
            debug.cord.pull(dx: 0, dy: pull)
        }
    }

    /// The cord's window is wide so it never clips, so only the rope itself may catch the mouse.
    func installCordHitTesting() {
        NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in self?.pointerMoved(event) }
        NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.pointerMoved(event)
            return event
        }
        updateCordHitTesting()
    }

    func pointerMoved(_ event: NSEvent) {
        updateCordHitTesting()
        if isPointerNearWidget() {
            lastActivity = Date()
            if debug.tucked { debug.tucked = false }
            if debug.prototype == .cord { debug.cord.wake() }
        }
        let mouse = NSEvent.mouseLocation
        let point = CGPoint(x: mouse.x - handle.frame.minX, y: handle.frame.maxY - mouse.y)
        switch debug.prototype {
        case .cord:
            if debug.cord.isNear(point, within: 6) { debug.cord.brush(at: point, dx: event.deltaX) }
        case .bird:
            followWithBird(point)
        }
    }

    /// The bird notices the pointer from well outside its window, and pauses before looking away.
    func followWithBird(_ point: CGPoint) {
        let distance = hypot(point.x - 32, point.y - 32)
        if distance <= Self.birdNoticeRadius {
            birdLookAway?.cancel()
            birdLookAway = nil
            debug.birdPointer = point
        } else if debug.birdPointer != nil, birdLookAway == nil {
            let work = DispatchWorkItem { [weak self] in
                self?.debug.birdPointer = nil
                self?.birdLookAway = nil
            }
            birdLookAway = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }

    /// Clicks pass through wherever the widget draws nothing: the cord by its rope's shape, the
    /// bird by the pixel under the pointer. Never changed mid-drag.
    func updateCordHitTesting() {
        guard NSEvent.pressedMouseButtons == 0 else { return }
        let mouse = NSEvent.mouseLocation
        guard debug.prototype == .cord else {
            guard handle.frame.contains(mouse), let view = handle.contentView else { return }
            let local = view.convert(handle.convertPoint(fromScreen: mouse), from: nil)
            handle.ignoresMouseEvents = !WidgetHitTest.isDrawn(at: local, in: view)
            return
        }
        let lifted = debug.tucked ? debug.prototype.tuckDistance : 0
        let point = CGPoint(x: mouse.x - handle.frame.minX, y: handle.frame.maxY - mouse.y + lifted)
        handle.ignoresMouseEvents = !debug.cord.isNear(point)
    }

    /// Slides along the top edge of whichever display the pointer is on.
    func slideCord(toLeft left: CGFloat) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? handle.screen ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let x = min(max(left, visible.minX), visible.maxX - handle.frame.width)
        debug.cord.carry(dx: x - handle.frame.minX)
        handle.setFrameOrigin(NSPoint(x: x, y: visible.maxY - handle.frame.height))
    }

    func applyPrototype() {
        handle.setFrame(widgetFrame(), display: true)
        updateCordHitTesting()
    }
}
