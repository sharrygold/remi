import AppKit

/// Remi on a swing at the end of the knotted cord, hanging from the top edge. `CordMotion` decides
/// what each frame looks like; this view only applies it, and stops its clock when nothing moves.
final class CordCompanionView: NSView, CompanionSurface {
    private static let scale: CGFloat = 240.0 / 230
    private static let stageHeight: CGFloat = 297
    static let windowSize = CGSize(width: 200, height: stageHeight * scale)
    private static let art = CGSize(width: 120, height: 230)
    private static let braidArt = CGSize(width: 120, height: 160)
    private static let knotArt = CGSize(width: 12, height: 10)
    private static let maxKnots = 14

    let motion = CordMotion()
    private var plumage = Plumage.ivory
    private var knotCount = 0
    private var link: CADisplayLink?
    private var lastTick = 0.0
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var lastFrame = CordFrame()
    private var lastPullTarget = CordMotion.tuckedPull

    private let stage = CALayer()
    private let mount = CALayer()
    private let swayGroup = CALayer.pivot(at: CGPoint(x: 60, y: 0), canvas: art)
    private let braidGroup = CALayer()
    private let braid = CALayer()
    private var knots: [CALayer] = []
    private let swingCarrier = CALayer()
    private let swingRock = CALayer.pivot(at: CGPoint(x: 60, y: 160), canvas: art)
    private let swing = CALayer()
    private let remiGroup = CALayer.pivot(at: CGPoint(x: 60, y: 207.2), canvas: art)
    private let remi = CALayer()
    private let eyelid = CALayer()
    private let ring = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        buildLayers()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func buildLayers() {
        let art = Self.art
        stage.bounds = CGRect(x: 0, y: 0, width: 120, height: Self.stageHeight)
        stage.anchorPoint = CGPoint(x: 0.5, y: 1)
        stage.position = CGPoint(x: Self.windowSize.width / 2, y: Self.windowSize.height)
        stage.transform = CATransform3DMakeScale(Self.scale, Self.scale, 1)
        layer?.addSublayer(stage)

        let topOffset = Self.stageHeight - art.height
        mount.frame = CGRect(x: 0, y: topOffset, width: art.width, height: art.height)
        swayGroup.position = CGPoint(x: 60, y: Self.stageHeight)
        stage.addSublayer(swayGroup)

        braidGroup.bounds = CGRect(origin: .zero, size: Self.braidArt)
        braidGroup.anchorPoint = CGPoint(x: 0.5, y: 1)
        braidGroup.position = CGPoint(x: 60, y: art.height)
        swayGroup.addSublayer(braidGroup)
        braid.frame = CGRect(origin: .zero, size: Self.braidArt)
        braidGroup.addSublayer(braid)

        swingCarrier.frame = CGRect(origin: .zero, size: art)
        swayGroup.addSublayer(swingCarrier)
        swingCarrier.addSublayer(swingRock)
        swing.frame = CGRect(origin: .zero, size: art)
        swingRock.addSublayer(swing)
        swingRock.addSublayer(remiGroup)
        remi.frame = CGRect(origin: .zero, size: art)
        eyelid.frame = CGRect(origin: .zero, size: art)
        remiGroup.addSublayer(remi)
        remiGroup.addSublayer(eyelid)

        // The ring pulses from the egg on Remi's back, in the mark's own coordinates.
        ring.path = CGPath(ellipseIn: CGRect(x: -3.5, y: -3.5, width: 7, height: 7), transform: nil)
        ring.position = CGPoint(x: 60 + (45 - 58) * 0.38, y: art.height - (207.2 + (41.5 - 102.4) * 0.38))
        ring.fillColor = nil
        ring.lineWidth = 0.9
        ring.opacity = 0
        remiGroup.addSublayer(ring)
        stage.addSublayer(mount)
    }

    // MARK: CompanionSurface

    func configure(plumage: Plumage, onLeftEdge: Bool) {
        self.plumage = plumage
        let art = Self.art, scale = window?.backingScaleFactor ?? 2
        withoutAnimation {
            for (layer, name) in [(mount, "cord-mount"), (swing, "cord-swing"), (remi, "cord-remi"), (eyelid, "cord-eyelid")] {
                layer.contents = CompanionArt.image(name, plumage: plumage, canvas: art)
                layer.contentsScale = scale
                layer.minificationFilter = .trilinear
            }
            braid.contents = CompanionArt.image("cord-braid", plumage: plumage, canvas: Self.braidArt)
            braid.contentsScale = scale
            ring.strokeColor = NSColor(hex: plumage.colourway.cord.metal).cgColor
            let image = CompanionArt.image("cord-knot", plumage: plumage, canvas: Self.knotArt)
            knots.forEach { $0.contents = image }
        }
        motion.reduceMotion = reduceMotion
        syncTucking()
        startClock()
    }

    func syncTucking() {
        motion.autoTuck = UserDefaults.standard.object(forKey: SettingsKey.autoTuck) as? Bool ?? true
    }

    func reduceMotionChanged() {
        motion.reduceMotion = reduceMotion
        startClock()
    }

    private func knotPosition(_ index: Int) -> CGPoint {
        CGPoint(x: 60, y: Self.braidArt.height - (20 + 10 * CGFloat(index)))
    }

    private func makeKnot(at index: Int) -> CALayer {
        let knot = CALayer()
        knot.bounds = CGRect(origin: .zero, size: Self.knotArt)
        knot.position = knotPosition(index)
        knot.contents = CompanionArt.image("cord-knot", plumage: plumage, canvas: Self.knotArt)
        knot.contentsScale = window?.backingScaleFactor ?? 2
        braidGroup.addSublayer(knot)
        return knot
    }

    func update(count: Int, allKept: Bool, event: CompanionEvent?) {
        let showing = UserDefaults.standard.object(forKey: SettingsKey.showCount) as? Bool ?? true
        let target = showing ? min(count, Self.maxKnots) : 0
        let now = CACurrentMediaTime()
        withoutAnimation {
            // Grow or shrink to match; the newest knot is tied on below if a task was just added.
            while knots.count < target { knots.append(makeKnot(at: knots.count)) }
        }
        switch event {
        case .taskAdded:
            motion.fire(.taskAdded, now: now)
            if target > knotCount, let knot = knots.last { tie(knot, index: knots.count - 1) }
        case .linkCaught:
            motion.fire(.linkCaught, now: now)
            pulseRing()
            // A link isn't a task, so its knot ties on and then loosens: the count stays honest.
            if knots.count < Self.maxKnots {
                let index = knots.count
                let knot = withoutAnimationResult { makeKnot(at: index) }
                tie(knot, index: index, delay: 0.3)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in self?.loosen(knot, delay: 0) }
            }
        case .taskDone:
            motion.fire(.taskDone, now: now)
        case .allDone:
            motion.fire(.allDone, now: now)
        case nil:
            break
        }
        // Remove from the bottom: a finished task's knot loosens, anything else just goes.
        var delay = 0.0
        while knots.count > target, let knot = knots.popLast() {
            if event == .taskDone || event == .allDone {
                loosen(knot, delay: delay)
                delay += 0.08
            } else {
                knot.removeFromSuperlayer()
            }
        }
        knotCount = knots.count
        startClock()
    }

    private func withoutAnimationResult<T>(_ work: () -> T) -> T {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        return work()
    }

    /// Slides from the mount to its slot, then cinches with a squash.
    private func tie(_ knot: CALayer, index: Int, delay: Double = 0) {
        let begin = CACurrentMediaTime() + delay
        guard !reduceMotion else {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.2
            fade.beginTime = begin
            fade.fillMode = .backwards
            knot.add(fade, forKey: "tie")
            return
        }
        let slide = CABasicAnimation(keyPath: "position.y")
        slide.fromValue = Self.braidArt.height
        slide.toValue = knotPosition(index).y
        slide.duration = 0.5
        slide.beginTime = begin
        slide.fillMode = .backwards
        slide.timingFunction = CAMediaTimingFunction(name: .easeIn)
        knot.add(slide, forKey: "tieSlide")
        let cinch = CAKeyframeAnimation(keyPath: "transform")
        cinch.values = [CATransform3DMakeScale(1, 1, 1), CATransform3DMakeScale(1.3, 0.75, 1), CATransform3DIdentity].map { NSValue(caTransform3D: $0) }
        cinch.duration = 0.3
        cinch.beginTime = begin + 0.5
        knot.add(cinch, forKey: "tieCinch")
    }

    /// Swells a little, then fades as it drops away.
    private func loosen(_ knot: CALayer, delay: Double) {
        let begin = CACurrentMediaTime() + delay
        CATransaction.begin()
        CATransaction.setCompletionBlock { knot.removeFromSuperlayer() }
        if !reduceMotion {
            let swell = CABasicAnimation(keyPath: "transform.scale")
            swell.fromValue = 1
            swell.toValue = 1.15
            let drop = CABasicAnimation(keyPath: "position.y")
            drop.byValue = -6
            let group = CAAnimationGroup()
            group.animations = [swell, drop]
            group.duration = 0.5
            group.beginTime = begin
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false
            knot.add(group, forKey: "loosenMove")
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = reduceMotion ? 0.2 : 0.5
        fade.beginTime = begin
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        knot.add(fade, forKey: "loosenFade")
        CATransaction.commit()
    }

    private func pulseRing() {
        guard !reduceMotion else { return }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1
        scale.toValue = 2.6
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 1
        ring.add(group, forKey: "ring")
    }

    func setPanelOpen(_ open: Bool) {
        motion.setPanelOpen(open, now: CACurrentMediaTime())
        startClock()
    }

    func playMorningStretch() {
        motion.fire(.stretch, now: CACurrentMediaTime())
        startClock()
    }

    func pointerMoved(toScreen point: NSPoint) {
        guard let window else { return }
        let x = point.x - window.frame.midX
        let y = window.frame.maxY - point.y
        // Within about 120 pt of the cord's line, from the top edge down to its full length.
        let near = abs(x) <= 120 && y >= -24 && y <= 300
        let now = CACurrentMediaTime()
        motion.pointer(near: near, now: now)
        // The mark's head is part of its silhouette, so Remi leans toward you instead of turning it alone.
        let swingY = (207 + lastFrame.pull) * Self.scale
        let toward = near ? Double(atan2(x, max(abs(y - swingY), 40)) * 180 / .pi) * 0.5 : 0
        motion.look(toward: toward)
        if near || !motion.isAtRest { startClock() }
    }

    func click() {
        motion.fire(.click, now: CACurrentMediaTime())
        startClock()
    }

    func beginPull() {
        motion.startPull()
        startClock()
    }

    func drag(by points: CGFloat) {
        motion.drag(by: Double(points / Self.scale))
        startClock()
    }

    func endPull() -> Bool {
        defer { startClock() }
        return motion.release(now: CACurrentMediaTime())
    }

    func carry(dx: CGFloat) {
        motion.carry(dx: Double(dx), now: CACurrentMediaTime())
        startClock()
    }

    /// Screenshots: put the cord in a given pose without waiting.
    func preview(state: String, pull: Double?) {
        let now = CACurrentMediaTime()
        switch state {
        case "lowered": motion.pointer(near: true, now: now + 3600)
        case "panel": motion.setPanelOpen(true, now: now)
        default: break
        }
        if let pull {
            motion.pointer(near: true, now: now + 3600)
            motion.startPull()
            motion.drag(by: pull)
        }
    }

    // MARK: Frames

    func startClock() {
        guard window != nil else { return }
        if link == nil {
            let link = displayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
            lastTick = CACurrentMediaTime()
        }
        if link?.isPaused == true {
            link?.isPaused = false
            lastTick = CACurrentMediaTime()
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.05)
        lastTick = now
        syncTucking()
        let frame = motion.tick(now: now, dt: dt)
        fadeThroughJumpIfNeeded()
        apply(frame)
        lastFrame = frame
        // At rest nothing is left to draw, so no timer runs at all.
        if motion.isAtRest { link.isPaused = true }
    }

    /// With Reduce Motion, tuck and lower become a 0.2 s fade instead of travelling.
    private func fadeThroughJumpIfNeeded() {
        let target = motion.pullTarget
        defer { lastPullTarget = target }
        guard reduceMotion, abs(target - lastPullTarget) > 60 else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.2
        stage.add(fade, forKey: "fade")
    }

    private func apply(_ f: CordFrame) {
        withoutAnimation {
            swayGroup.transform = CATransform3DMakeRotation(radians(-(f.sway + f.lean)), 0, 0, 1)
            let stretch = max((160 + f.pull) / 160, 0.05)
            braidGroup.transform = CATransform3DMakeScale(1, CGFloat(stretch), 1)
            swingCarrier.transform = CATransform3DMakeTranslation(0, CGFloat(-f.pull), 0)
            swingRock.transform = CATransform3DMakeRotation(radians(-f.rock), 0, 0, 1)
            var remiTransform = CATransform3DMakeTranslation(0, CGFloat(f.hop + f.bob), 0)
            remiTransform = CATransform3DRotate(remiTransform, radians(-f.tilt), 0, 0, 1)
            let squatX = 1 + 0.04 * f.squat, squatY = 1 - 0.06 * f.squat
            remiTransform = CATransform3DScale(remiTransform, CGFloat(squatX * f.breath * f.puff), CGFloat(squatY * f.breath * f.puff), 1)
            remiGroup.transform = remiTransform
            eyelid.isHidden = !f.eyesClosed
        }
    }

    // MARK: Hit testing

    func isHit(_ point: CGPoint) -> Bool {
        let dx = abs(point.x - Self.windowSize.width / 2)
        let pull = lastFrame.pull
        let ringY = (160 + pull) * Self.scale, barY = (212 + pull) * Self.scale
        if point.y >= ringY - 4 { return point.y <= barY + 8 && dx <= 34 }
        return point.y <= ringY && dx <= 14
    }
}
