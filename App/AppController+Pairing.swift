import AppKit

/// The companion and the open panel move as one: carry the bird and the panel comes along, drag the
/// panel and the bird comes along. Let go away from the edge and the pair hangs for a moment, then
/// glides back so the companion is on the edge again.
extension AppController {
    /// How long a drop away from the edge hangs in the air before gliding back.
    static let hoverBeforeGlide: TimeInterval = 0.8
    /// The glide back from the open, and the quick settle from near the edge.
    static let glideSeconds: TimeInterval = 1.2
    static let snapSeconds: TimeInterval = 0.32

    /// Ease in and out with no sudden start or stop: speed and acceleration are both zero at each end.
    static func smootherStep(_ t: Double) -> Double { t * t * t * (t * (t * 6 - 15) + 10) }

    /// Eases out past the target a little and back, for a short settle near the edge.
    static func softOvershoot(_ t: Double) -> Double {
        let c1 = 1.1, c3 = c1 + 1
        return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
    }

    /// Moves windows to new frames together, one step per screen refresh. The window server's own
    /// frame animation stepped visibly on a long glide; this stays smooth.
    func glide(_ moves: [(window: NSWindow, to: NSRect)], seconds: TimeInterval, curve: @escaping (Double) -> Double,
               completion: @escaping () -> Void) {
        glideTimer?.invalidate()
        let starts = moves.map(\.window.frame)
        let begin = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] timer in
            let progress = min((CACurrentMediaTime() - begin) / seconds, 1)
            let eased = CGFloat(curve(progress))
            for (index, move) in moves.enumerated() {
                let from = starts[index]
                move.window.setFrame(NSRect(x: from.minX + (move.to.minX - from.minX) * eased,
                                            y: from.minY + (move.to.minY - from.minY) * eased,
                                            width: from.width + (move.to.width - from.width) * eased,
                                            height: from.height + (move.to.height - from.height) * eased), display: true)
            }
            guard progress >= 1 else { return }
            timer.invalidate()
            self?.glideTimer = nil
            completion()
        }
        RunLoop.main.add(timer, forMode: .common)
        glideTimer = timer
    }

    func stopGlide() {
        glideTimer?.invalidate()
        glideTimer = nil
        settling = false
    }
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
        let offset = NSPoint(x: handle.frame.minX - panel.frame.minX, y: handle.frame.minY - panel.frame.minY)
        panel.addChildWindow(handle, ordered: .above)
        // Linked too soon after the panel appears, the window server once moved the bird to a stale
        // spot a moment later. If that happens, put it back beside the panel.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.handle.parent === self.panel, !self.settling else { return }
            let expected = NSPoint(x: self.panel.frame.minX + offset.x, y: self.panel.frame.minY + offset.y)
            if hypot(self.handle.frame.minX - expected.x, self.handle.frame.minY - expected.y) > 1 {
                self.handle.setFrameOrigin(expected)
            }
        }
    }

    func detachCompanion() {
        if handle.parent != nil { panel.removeChildWindow(handle) }
    }

    func installPanelFollowing() {
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            self?.panelDidMove()
        }
        // While the panel is resized the companion is unlinked, or a moving left edge would drag it along.
        for name in [NSWindow.willStartLiveResizeNotification, NSWindow.didEndLiveResizeNotification] {
            NotificationCenter.default.addObserver(forName: name, object: panel, queue: .main) { [weak self] note in
                guard let self else { return }
                self.resizingPanel = note.name == NSWindow.willStartLiveResizeNotification
                if self.resizingPanel { self.detachCompanion() } else { self.attachCompanion() }
            }
        }
        panel.onResizeStart = { [weak self] in self?.detachCompanion() }
        panel.onResizeFinish = { [weak self] in self?.attachCompanion() }
        panel.companionFrame = { [weak self] in self?.handle.frame }
    }

    /// The user dragged the panel: the companion has come along as a child window. Once the mouse
    /// is let go, the pair settles.
    private func panelDidMove() {
        guard panelMovesByCode == 0, !settling, !resizingPanel, !panel.isResizingByHand, carryOffset == nil,
              presentation.presented, !watchingPanelDrop else { return }
        watchingPanelDrop = true
        stopGlide()
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
        stopGlide()
        settleToken += 1
        perched?.setCarried(true)
        guard presentation.presented else { return }
        detachCompanion()
        carryOffset = NSPoint(x: panel.frame.minX - handle.frame.minX, y: panel.frame.minY - handle.frame.minY)
    }

    func companionMoved() {
        guard var offset = carryOffset else { return }
        // Carried past the middle of the screen: the panel changes sides so it stays on screen and
        // the bird turns to face it. It blinks across rather than sliding behind the bird.
        let visible = screen(for: handle.frame).visibleFrame
        let birdOnLeft = handle.frame.midX < visible.midX
        let panelOnLeft = offset.x < 0
        if birdOnLeft == panelOnLeft {
            offset.x = birdOnLeft ? handle.frame.width + Tokens.Size.handleGap : -panel.frame.width - Tokens.Size.handleGap
            carryOffset = offset
            onLeftEdge = birdOnLeft
            surface.configure(plumage: companion.plumage, onLeftEdge: onLeftEdge)
            swapPanelSide { [weak self] in
                guard let self else { return }
                self.presentation.anchor = self.panelAnchor(for: self.handle.frame, panelFrame: self.panel.frame)
            }
        }
        movingPanel { panel.setFrameOrigin(NSPoint(x: handle.frame.minX + offset.x, y: handle.frame.minY + offset.y)) }
    }

    /// Fades the panel out, lets `move` put it on the other side, then fades it back in.
    /// The window keeps following the pointer the whole time; only its opacity animates.
    func swapPanelSide(_ move: @escaping () -> Void) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            move()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.presentation.presented else { return }
            move()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.panel.animator().alphaValue = 1
            }
        })
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
            // The panel is on the wrong side of the bird (it was dragged across the screen): it fades
            // out while the bird glides, then eases in on the right side from the bird's direction.
            if let panelTarget, (self.panel.frame.midX < self.handle.frame.midX) != (panelTarget.midX < target.midX) {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.14
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    self.panel.animator().alphaValue = 0
                }, completionHandler: nil)
                self.glide([(self.handle, target)], seconds: far ? Self.glideSeconds : Self.snapSeconds,
                           curve: Self.smootherStep, completion: { [weak self] in
                    guard let self, token == self.settleToken, self.presentation.presented else {
                        self?.panel.alphaValue = 1
                        self?.settling = false
                        return
                    }
                    let fromBird: CGFloat = panelTarget.midX > target.midX ? -12 : 12
                    self.panel.setFrame(panelTarget.offsetBy(dx: fromBird, dy: 0), display: true)
                    NSAnimationContext.runAnimationGroup({ context in
                        context.duration = 0.24
                        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                        self.panel.animator().alphaValue = 1
                        self.panel.animator().setFrame(panelTarget, display: true)
                    }, completionHandler: finish)
                })
                return
            }
            // From the open: slow to leave and slow to arrive, like something lowered into place.
            // Near the edge: a short settle with a slight overshoot.
            var moves: [(window: NSWindow, to: NSRect)] = [(self.handle, target)]
            if let panelTarget { moves.append((self.panel, panelTarget)) }
            self.glide(moves, seconds: far ? Self.glideSeconds : Self.snapSeconds,
                       curve: far ? Self.smootherStep : Self.softOvershoot, completion: finish)
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
        steps.append((2.0, { [self] in
            print("landed  bird=\(f(handle.frame)) panel=\(f(panel.frame)) gap=\(Int(gap())) child=\(handle.parent === panel) edge=\(Int(screen(for: handle.frame).visibleFrame.maxX - handle.frame.maxX))")
            // The user drags the panel up by 120: the bird is its child, so it comes too.
            panel.setFrameOrigin(NSPoint(x: panel.frame.minX - 200, y: panel.frame.minY + 120))
            print("panel dragged bird=\(f(handle.frame)) panel=\(f(panel.frame)) child=\(handle.parent === panel) children=\(panel.childWindows?.count ?? -1)")
        }))
        steps.append((0.05, { [self] in print("50ms later bird=\(f(handle.frame))") }))
        steps.append((2.6, { [self] in
            print("settled bird=\(f(handle.frame)) panel=\(f(panel.frame)) gap=\(Int(gap())) edge=\(Int(screen(for: handle.frame).visibleFrame.maxX - handle.frame.maxX))")
            hidePanel()
        }))
        steps.append((0.6, { [self] in
            showPanel()
        }))
        steps.append((0.8, { [self] in
            // Widen from the far edge, then push the edge next to the bird into it.
            let bird = handle.frame
            let left = PanelResize(window: panel, edges: [.left])
            left.follow(NSPoint(x: left.startMouse.x - 100, y: left.startMouse.y))
            left.end()
            print("resize left  width=\(Int(panel.frame.width)) birdMoved=\(handle.frame != bird) child=\(handle.parent === panel)")
            let right = PanelResize(window: panel, edges: [.right])
            right.follow(NSPoint(x: right.startMouse.x + 300, y: right.startMouse.y))
            right.end()
            print("resize right width=\(Int(panel.frame.width)) birdMoved=\(handle.frame != bird) gapToBird=\(Int(handle.frame.minX - panel.frame.maxX))")
            panel.setContentSize(NSSize(width: 385, height: 603))
            hidePanel()
        }))
        steps.append((0.5, { [self] in
            showPanel()
            // Carry the bird across to the left half: the panel should swap to its right.
            beginCarry()
            let visible = screen(for: handle.frame).visibleFrame
            handle.setFrameOrigin(NSPoint(x: visible.minX + 200, y: handle.frame.minY))
            companionMoved()
            print("crossed bird=\(f(handle.frame)) panel=\(f(panel.frame)) panelRightOfBird=\(panel.frame.minX > handle.frame.maxX) leftEdge=\(onLeftEdge)")
            settleCompanion()
        }))
        steps.append((2.6, { [self] in
            let visible = screen(for: handle.frame).visibleFrame
            print("crossed landed bird=\(f(handle.frame)) panel=\(f(panel.frame)) onLeft=\(Int(handle.frame.minX - visible.minX)) gap=\(Int(gap())) alpha=\(panel.alphaValue)")
            // Now drag the panel to the right half; the bird should go to the right edge and the panel swap to its left.
            panel.setFrameOrigin(NSPoint(x: visible.maxX - 500, y: panel.frame.minY))
        }))
        steps.append((3.0, { [self] in
            let visible = screen(for: handle.frame).visibleFrame
            print("dragged back bird=\(f(handle.frame)) panel=\(f(panel.frame)) onRight=\(Int(visible.maxX - handle.frame.maxX)) panelLeftOfBird=\(panel.frame.maxX < handle.frame.minX) alpha=\(panel.alphaValue) child=\(handle.parent === panel)")
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
