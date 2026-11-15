import AppKit

/// The companion and the open panel move as one: carry the bird and the panel comes along, drag the
/// panel and the bird comes along. Let go away from the edge and the pair hangs for a moment, then
/// glides back so the companion is on the edge again.
extension AppController {
    /// How long a drop away from the edge hangs in the air before gliding back.
    static let hoverBeforeGlide: TimeInterval = 0.8
    /// Further than this from its spot on the edge counts as a drop in the open.
    static let farFromEdge: CGFloat = 48

    func movingPanel(_ work: () -> Void) {
        panelMovesByCode += 1
        work()
        panelMovesByCode -= 1
    }

    /// While the panel is open the companion is its child window, so the window server moves it
    /// with the panel during a drag, with no lag.
    func attachCompanion() {
        guard presentation.presented, handle.parent == nil, handle.isVisible else { return }
        panel.addChildWindow(handle, ordered: .above)
    }

    func detachCompanion() {
        if handle.parent != nil { panel.removeChildWindow(handle) }
    }

    func installPanelFollowing() {
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            self?.panelDidMove()
        }
        for name in [NSWindow.willStartLiveResizeNotification, NSWindow.didEndLiveResizeNotification] {
            NotificationCenter.default.addObserver(forName: name, object: panel, queue: .main) { [weak self] note in
                self?.resizingPanel = note.name == NSWindow.willStartLiveResizeNotification
            }
        }
    }

    /// The user dragged the panel: the companion has come along as a child window. Once the mouse
    /// is let go, the pair settles.
    private func panelDidMove() {
        guard panelMovesByCode == 0, !settling, !resizingPanel, !panel.isResizingByHand, carryOffset == nil,
              presentation.presented, !watchingPanelDrop else { return }
        watchingPanelDrop = true
        settleToken += 1
        perched?.setCarried(true)
        // The move notice arrives before the child window has followed, so look again a moment later.
        DispatchQueue.main.async { [weak self] in self?.waitForPanelDrop() }
    }

    private func waitForPanelDrop() {
        guard NSEvent.pressedMouseButtons & 1 == 0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.waitForPanelDrop() }
            return
        }
        watchingPanelDrop = false
        settleCompanion()
    }

    func beginCarry() {
        settleToken += 1
        perched?.setCarried(true)
        guard presentation.presented else { return }
        detachCompanion()
        carryOffset = NSPoint(x: panel.frame.minX - handle.frame.minX, y: panel.frame.minY - handle.frame.minY)
    }

    func companionMoved() {
        guard let offset = carryOffset else { return }
        movingPanel { panel.setFrameOrigin(NSPoint(x: handle.frame.minX + offset.x, y: handle.frame.minY + offset.y)) }
    }

    /// Puts the companion back on the nearest edge (and the panel beside it), then remembers the spot.
    /// Near the edge it snaps with a soft overshoot; dropped in the open it hangs, then glides.
    func settleCompanion() {
        lastActivity = Date()
        carryOffset = nil
        settleToken += 1
        let token = settleToken
        let style = companion.style
        let screen = screen(for: handle.frame)
        let placement = WidgetPlacement.nearest(to: handle.frame, prototype: style, on: screen.visibleFrame)
        PlacementStore.save(placement, prototype: style, on: screen)
        let target = placement.frame(for: style, on: screen.visibleFrame)
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let far = hypot(target.midX - handle.frame.midX, target.midY - handle.frame.midY) > Self.farFromEdge && !reduce
        if !far { perched?.setCarried(false) }

        let land = { [weak self] in
            guard let self, token == self.settleToken else { return }
            self.onLeftEdge = placement.onLeftEdge
            self.surface.configure(plumage: self.companion.plumage, onLeftEdge: self.onLeftEdge)
            let panelTarget = self.presentation.presented ? self.panelFrame(beside: target) : nil
            self.detachCompanion()
            let finish = { [weak self] in
                guard let self else { return }
                self.settling = false
                if token == self.settleToken { self.perched?.setCarried(false) }
                if let panelTarget, self.presentation.presented {
                    self.presentation.anchor = self.panelAnchor(for: target, panelFrame: panelTarget)
                    self.attachCompanion()
                }
                self.updateMouseCatching()
            }
            self.settling = true
            if reduce {
                self.handle.setFrame(target, display: true)
                if let panelTarget { self.panel.setFrame(panelTarget, display: true) }
                finish()
                return
            }
            NSAnimationContext.runAnimationGroup({ context in
                if far {
                    // Slow to leave and slow to arrive, like something lowered into place.
                    context.duration = 0.9
                    context.timingFunction = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.2, 1)
                } else {
                    context.duration = 0.32
                    context.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 1.25, 0.5, 1)
                }
                self.handle.animator().setFrame(target, display: true)
                if let panelTarget { self.panel.animator().setFrame(panelTarget, display: true) }
            }, completionHandler: finish)
        }
        if far {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverBeforeGlide, execute: land)
        } else {
            land()
        }
    }
}

extension AppController {
    /// Moves the companion and panel by code, with no mouse, and prints where each ends up.
    /// Run with --demo-data --no-focus --pair-selftest.
    func runPairSelfTest() {
        func f(_ r: NSRect) -> String { "(\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height)))" }
        func gap() -> CGFloat { min(abs(panel.frame.maxX - handle.frame.minX), abs(handle.frame.maxX - panel.frame.minX)) }
        var steps: [(TimeInterval, () -> Void)] = []
        steps.append((1.0, { [self] in
            showPanel()
            print("open    bird=\(f(handle.frame)) panel=\(f(panel.frame)) child=\(handle.parent === panel)")
        }))
        steps.append((0.6, { [self] in
            // Carry the bird 300 pt left and 150 down, into the open.
            beginCarry()
            handle.setFrameOrigin(NSPoint(x: handle.frame.minX - 300, y: handle.frame.minY - 150))
            companionMoved()
            print("carried bird=\(f(handle.frame)) panel=\(f(panel.frame)) gap=\(Int(gap()))")
            settleCompanion()
        }))
        steps.append((0.4, { [self] in print("hover   bird=\(f(handle.frame)) (should still be in the open)") }))
        steps.append((1.6, { [self] in
            print("landed  bird=\(f(handle.frame)) panel=\(f(panel.frame)) gap=\(Int(gap())) child=\(handle.parent === panel) edge=\(Int(screen(for: handle.frame).visibleFrame.maxX - handle.frame.maxX))")
            // The user drags the panel up by 120: the bird is its child, so it comes too.
            panel.setFrameOrigin(NSPoint(x: panel.frame.minX - 200, y: panel.frame.minY + 120))
            print("panel dragged bird=\(f(handle.frame)) panel=\(f(panel.frame)) child=\(handle.parent === panel) children=\(panel.childWindows?.count ?? -1)")
        }))
        steps.append((0.05, { [self] in print("50ms later bird=\(f(handle.frame))") }))
        steps.append((2.2, { [self] in
            print("settled bird=\(f(handle.frame)) panel=\(f(panel.frame)) gap=\(Int(gap())) edge=\(Int(screen(for: handle.frame).visibleFrame.maxX - handle.frame.maxX))")
            hidePanel()
        }))
        steps.append((0.5, { [self] in
            showPanel()
            print("reopen  visible=\(panel.isVisible) alpha=\(panel.alphaValue)")
            hidePanel()
        }))
        steps.append((0.1, { [self] in
            // Reopened while still fading out: must end up visible.
            showPanel()
        }))
        steps.append((0.6, { [self] in
            print("reopened mid-fade visible=\(panel.isVisible) alpha=\(panel.alphaValue) showing=\(panelIsShowing)")
            NSApp.terminate(nil)
        }))
        var delay: TimeInterval = 0
        for (wait, step) in steps {
            delay += wait
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: step)
        }
    }
}
