import AppKit

/// Remi perched on a gold peg at the side edge. Built from finished bitmap layers: loops run on the
/// render server, and the frame clock only runs while the head is actually moving.
final class PerchedBirdView: NSView, CompanionSurface {
    static let windowSize = CGSize(width: 108, height: 108)
    private static let scale: CGFloat = 0.9
    private static let canvas = CGSize(width: 120, height: 120)
    private static let tuckPoints = windowSize.width * 0.43
    private static let noticeRadius: CGFloat = 130

    enum Mood { case rest, working, dozing, tucked, carried }

    private(set) var mood = Mood.rest
    private var mirrored = false
    private var plumage = Plumage.ivory
    private var count = 0
    private var allKept = false
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private var head = HeadFollow()
    private lazy var clock = FrameClock { [weak self] in self?.tick() }
    private var lastTick = 0.0
    private var lookAway: DispatchWorkItem?
    private var noticing = false

    private let slider = CALayer()
    private let stage = CALayer()
    private let peg = CALayer(), legs = CALayer(), feet = CALayer()
    private let birdRoot = CALayer.pivot(at: CGPoint(x: 60, y: 104), canvas: canvas)
    private let tail = CALayer.pivot(at: CGPoint(x: 34, y: 82), canvas: canvas)
    private let breath = CALayer.pivot(at: CGPoint(x: 60, y: 104), canvas: canvas)
    private let bodyLayer = CALayer()
    private let wing = CALayer.pivot(at: CGPoint(x: 74, y: 70), canvas: canvas)
    private let cradle = CALayer(), neck = CALayer()
    private let eggPlace = CALayer.centred(at: CGPoint(x: 52, y: 56), canvas: canvas)
    private let eggRock = CALayer.pivot(at: CGPoint(x: 60, y: 60), canvas: canvas)
    private let eggWobble = CALayer.pivot(at: CGPoint(x: 60, y: 60), canvas: canvas)
    private let eggImage = CALayer()
    private let countLayer = CALayer()
    private let checkLayer = CAShapeLayer()
    private let ring = CAShapeLayer()
    private let headBob = CALayer.centred(at: CGPoint(x: 81, y: 35), canvas: canvas)
    private let headSpin = CALayer.pivot(at: CGPoint(x: 60, y: 60), canvas: canvas)
    private let crest = CALayer.pivot(at: CGPoint(x: 51, y: 60), canvas: canvas)
    private let skull = CALayer()
    private let eye = CALayer.pivot(at: CGPoint(x: 63, y: 60), canvas: canvas)
    private let headShade = CALayer(), headDoze = CALayer()

    private var artLayers: [(CALayer, String)] {
        [(peg, "perched-peg"), (legs, "perched-legs"), (feet, "perched-feet"), (tail, "perched-tail"), (bodyLayer, "perched-body"),
         (wing, "perched-wing"), (cradle, "perched-cradle"), (neck, "perched-neck"), (eggImage, "perched-egg"), (crest, "perched-crest"),
         (skull, "perched-head"), (eye, "perched-eye"), (headShade, "perched-head-shade"), (headDoze, "perched-head-doze")]
    }

    private var hitMask: (data: [UInt8], width: Int)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        buildLayers()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func buildLayers() {
        let canvas = Self.canvas
        for layer in [peg, legs, feet, bodyLayer, cradle, neck, eggImage, skull, headShade, headDoze] {
            layer.frame = CGRect(origin: .zero, size: canvas)
        }
        slider.bounds = CGRect(origin: .zero, size: Self.windowSize)
        slider.anchorPoint = .zero
        slider.position = .zero
        layer?.addSublayer(slider)
        stage.bounds = CGRect(origin: .zero, size: canvas)
        stage.position = CGPoint(x: Self.windowSize.width / 2, y: Self.windowSize.height / 2)
        // Hold the edge: a faint outline of the whole silhouette, so it reads on any wallpaper.
        stage.shadowOpacity = 0.25
        stage.shadowRadius = 1
        stage.shadowOffset = .zero
        slider.addSublayer(stage)

        // Back to front: peg, legs, body with wing and neck, egg, head, head light.
        stage.addSublayer(peg)
        stage.addSublayer(birdRoot)
        birdRoot.addSublayer(legs)
        birdRoot.addSublayer(feet)
        feet.isHidden = true
        birdRoot.addSublayer(tail)
        birdRoot.addSublayer(breath)
        for layer in [bodyLayer, wing, cradle, neck, eggPlace] { breath.addSublayer(layer) }
        eggPlace.transform = CATransform3DMakeRotation(radians(14), 0, 0, 1)
        eggPlace.addSublayer(eggRock)
        eggRock.addSublayer(eggWobble)
        eggImage.frame = CGRect(origin: .zero, size: canvas)
        eggWobble.addSublayer(eggImage)
        countLayer.bounds = CGRect(x: 0, y: 0, width: 40, height: 40)
        countLayer.position = CGPoint(x: 60, y: 60)
        countLayer.minificationFilter = .trilinear
        eggWobble.addSublayer(countLayer)
        let check = CGMutablePath()
        check.move(to: CGPoint(x: 55.5, y: 60))
        check.addLine(to: CGPoint(x: 59, y: 56.5))
        check.addLine(to: CGPoint(x: 65, y: 64))
        checkLayer.path = check
        checkLayer.fillColor = nil
        checkLayer.lineWidth = 1.7
        checkLayer.lineCap = .round
        checkLayer.lineJoin = .round
        checkLayer.isHidden = true
        eggWobble.addSublayer(checkLayer)
        ring.path = CGPath(ellipseIn: CGRect(x: -10.5, y: -10.5, width: 21, height: 21), transform: nil)
        ring.position = CGPoint(x: 60, y: 60)
        ring.fillColor = nil
        ring.lineWidth = 1.3
        ring.opacity = 0
        eggPlace.addSublayer(ring)

        breath.addSublayer(headBob)
        headBob.addSublayer(headSpin)
        for layer in [crest, skull, eye] { headSpin.addSublayer(layer) }
        skull.frame = CGRect(origin: .zero, size: canvas)
        breath.addSublayer(headShade)
        breath.addSublayer(headDoze)
        headDoze.isHidden = true

        applyHead()
    }

    // MARK: CompanionSurface

    func configure(plumage: Plumage, onLeftEdge: Bool) {
        self.plumage = plumage
        mirrored = !onLeftEdge
        let scale = window?.backingScaleFactor ?? 2
        withoutAnimation {
            for (layer, name) in artLayers {
                layer.contents = CompanionArt.image(name, plumage: plumage, canvas: Self.canvas)
                layer.contentsScale = scale
                layer.minificationFilter = .trilinear
            }
            stage.shadowColor = NSColor(hex: plumage.colourway.perched.halo).cgColor
            stage.transform = CATransform3DMakeScale(mirrored ? -Self.scale : Self.scale, Self.scale, 1)
            let egg = plumage.colourway.perched.eggText
            checkLayer.strokeColor = NSColor(hex: egg).cgColor
            ring.strokeColor = NSColor(hex: plumage.colourway.perched.metal).cgColor
            refreshCount()
        }
        hitMask = makeHitMask()
        applyMood()
    }

    func update(count: Int, allKept: Bool, event: CompanionEvent?) {
        let keptNow = allKept && !self.allKept
        self.count = count
        self.allKept = allKept
        withoutAnimation { refreshCount() }
        applyCrestRaise()
        switch event {
        case .taskAdded: playNewTask()
        case .linkCaught: playLinkCaught()
        case .taskDone, .allDone, nil: break
        }
        if keptNow { playPuff() }
    }

    func setPanelOpen(_ open: Bool) {
        if open {
            setMood(.working)
        } else if mood == .working {
            setMood(.rest)
        }
    }

    func setTucked(_ tucked: Bool) {
        if tucked, mood == .rest || mood == .dozing {
            setMood(.tucked)
        } else if !tucked, mood == .tucked {
            setMood(.rest)
        }
    }

    func setDozing(_ dozing: Bool) {
        if dozing, mood == .rest {
            setMood(.dozing)
        } else if !dozing, mood == .dozing {
            setMood(.rest)
        }
    }

    func setCarried(_ carried: Bool) {
        if carried {
            setMood(.carried)
        } else if mood == .carried {
            setMood(.rest)
        }
    }

    func reduceMotionChanged() { applyMood() }

    /// Screen coordinates. The bird only follows while resting or noticing.
    func pointerMoved(toScreen point: NSPoint) {
        guard mood == .rest, let window else { return }
        let local = toArtSpace(point, window: window)
        let distance = hypot(local.x - HeadFollow.pivot.x, local.y - HeadFollow.pivot.y) * Self.scale
        if distance <= Self.noticeRadius {
            lookAway?.cancel()
            lookAway = nil
            noticing = true
            head.aim(at: local)
            startClock()
        } else if noticing, lookAway == nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.noticing = false
                self.lookAway = nil
                self.head.move(to: HeadFollow.restT, returning: true)
                self.startClock()
            }
            lookAway = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }

    /// True when the pointer is close enough for the bird to notice it, even if it is tucked or dozing.
    func notices(_ point: NSPoint) -> Bool {
        guard let window else { return false }
        let local = toArtSpace(point, window: window)
        return hypot(local.x - HeadFollow.pivot.x, local.y - HeadFollow.pivot.y) * Self.scale <= Self.noticeRadius
    }

    /// For the self-test.
    var headReadout: (target: Double, angle: Double) { (head.angle.target, head.angle.value) }

    /// For screenshots: points the head as if the pointer were at this art-space position.
    func previewLook(at point: CGPoint) {
        head.aim(at: point)
        head.snapToTarget()
        applyHead()
    }

    private func toArtSpace(_ point: NSPoint, window: NSWindow) -> CGPoint {
        var x = (point.x - window.frame.minX - Self.windowSize.width / 2) / Self.scale + 60
        if mirrored { x = 120 - x }
        let y = (window.frame.maxY - point.y - Self.windowSize.height / 2) / Self.scale + 60
        return CGPoint(x: x, y: y)
    }

    // MARK: Moods

    func setMood(_ next: Mood) {
        guard next != mood else { return }
        let wasTucked = mood == .tucked
        mood = next
        if next != .rest {
            lookAway?.cancel()
            lookAway = nil
            noticing = false
        }
        applyMood()
        if wasTucked || next == .tucked { slide(tucked: next == .tucked) }
    }

    private func applyMood() {
        let dozing = mood == .dozing || mood == .tucked
        let carried = mood == .carried
        withoutAnimation {
            for layer in [neck, headBob, headShade] { layer.isHidden = dozing }
            headDoze.isHidden = !dozing
            peg.isHidden = carried
            legs.isHidden = carried
            feet.isHidden = !carried
            birdRoot.transform = carried ? CATransform3DMakeRotation(radians(9), 0, 0, 1) : CATransform3DIdentity
            wing.transform = carried ? CATransform3DMakeRotation(radians(-12), 0, 0, 1) : CATransform3DIdentity
        }
        installLoops()
        if mood == .working {
            head.move(to: HeadFollow.workingT)
        } else if mood == .rest, !noticing {
            head.move(to: HeadFollow.restT, returning: true)
        }
        if reduceMotion { head.snapToTarget(); applyHead() } else { startClock() }
    }

    /// Ambient motion runs as repeating Core Animation, which costs the app nothing between frames.
    private func installLoops() {
        for layer in [breath, eggRock, eye, tail, headBob] {
            for key in ["loop", "loop2"] { layer.removeAnimation(forKey: key) }
        }
        guard !reduceMotion else { return }
        switch mood {
        case .rest:
            breathe(period: 4.5)
            rockEgg()
            blink(every: 5)
            flickTail()
        case .working:
            breathe(period: 4.5)
            rockEgg()
            blink(every: 2.6)
            let bob = CABasicAnimation(keyPath: "transform.rotation.z")
            bob.fromValue = radians(-6)
            bob.toValue = radians(6)
            bob.duration = 1.1
            bob.autoreverses = true
            bob.repeatCount = .infinity
            bob.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            headBob.add(bob, forKey: "loop")
        case .dozing:
            breathe(period: 7)
        case .tucked, .carried:
            break
        }
    }

    private func breathe(period: Double) {
        for (path, to) in [("transform.scale.x", 1.025), ("transform.scale.y", 1.04)] {
            let animation = CABasicAnimation(keyPath: path)
            animation.fromValue = 1
            animation.toValue = to
            animation.duration = period / 2
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            breath.add(animation, forKey: path.hasSuffix("x") ? "loop" : "loop2")
        }
    }

    private func rockEgg() {
        let rock = CABasicAnimation(keyPath: "transform.rotation.z")
        rock.fromValue = radians(-3)
        rock.toValue = radians(3)
        rock.duration = 1.8
        rock.autoreverses = true
        rock.repeatCount = .infinity
        rock.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        eggRock.add(rock, forKey: "loop")
    }

    private func blink(every period: Double) {
        let blink = CAKeyframeAnimation(keyPath: "transform.scale.y")
        let close = 0.09 / period
        blink.values = [1, 1, 0.1, 1]
        blink.keyTimes = [0, NSNumber(value: 1 - 2 * close), NSNumber(value: 1 - close), 1]
        blink.duration = period
        blink.repeatCount = .infinity
        eye.add(blink, forKey: "loop")
    }

    private func flickTail() {
        let flick = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        flick.values = [0, 0, radians(5), radians(-3), 0]
        flick.keyTimes = [0, 0.93, 0.955, 0.98, 1]
        flick.duration = 9
        flick.repeatCount = .infinity
        tail.add(flick, forKey: "loop")
    }

    private func slide(tucked: Bool) {
        let offset = (mirrored ? 1 : -1) * Self.tuckPoints
        let to = tucked ? CGPoint(x: offset, y: 0) : .zero
        let from = slider.presentation()?.position ?? slider.position
        withoutAnimation { slider.position = to }
        guard !reduceMotion else { return }
        // Slight overshoot, about 0.55 s, and interruptible because it starts from where it is now.
        let spring = CASpringAnimation(keyPath: "position.x")
        spring.fromValue = from.x
        spring.toValue = to.x
        spring.mass = 1
        spring.stiffness = 170
        spring.damping = 18
        spring.duration = spring.settlingDuration
        slider.add(spring, forKey: "slide")
    }

    // MARK: One-shots

    private func playNewTask() {
        guard !reduceMotion, mood != .tucked else { return }
        let hop = CAKeyframeAnimation(keyPath: "transform.translation.y")
        hop.values = [0, 9, 0, 3, 0]
        hop.keyTimes = [0, 0.3, 0.6, 0.8, 1]
        hop.duration = 0.65
        birdRoot.add(hop, forKey: "hop")
        let wobble = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        wobble.values = [0, radians(9), radians(-8), radians(6), radians(-5), 0]
        wobble.duration = 1.9
        eggWobble.add(wobble, forKey: "wobble")
    }

    private func playLinkCaught() {
        guard !reduceMotion, mood != .tucked else { return }
        head.move(to: HeadFollow.restT)
        startClock()
        let peck = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        peck.values = [0, radians(-11), 0, radians(-11), 0, radians(-11), 0]
        peck.duration = 0.75
        peck.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        headBob.add(peck, forKey: "peck")
        pulseRing(after: 0)
        pulseRing(after: 0.5)
    }

    private func pulseRing(after delay: Double) {
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1
        scale.toValue = 2.6
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.9
        group.beginTime = CACurrentMediaTime() + delay
        ring.add(group, forKey: "ring\(delay)")
    }

    private func playPuff() {
        guard !reduceMotion else { return }
        let puff = CAKeyframeAnimation(keyPath: "transform.scale")
        puff.values = [1, 1.07, 1]
        puff.duration = 0.8
        stage.add(puff, forKey: "puff")
    }

    func playMorningStretch() {
        guard !reduceMotion, mood != .tucked else { return }
        let lift = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        lift.values = [0, radians(-16), 0, radians(-16), 0]
        lift.duration = 2.2
        lift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        wing.add(lift, forKey: "stretch")
        let shake = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        shake.values = [0, radians(6), radians(-6), radians(5), radians(-5), 0]
        shake.duration = 0.6
        shake.beginTime = CACurrentMediaTime() + 2.2
        headBob.add(shake, forKey: "shake")
    }

    // MARK: Frames

    private func startClock() {
        // Only when waking: resetting the time on every mouse event would starve the spring.
        guard !clock.isRunning else { return }
        lastTick = CACurrentMediaTime()
        clock.start()
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.05)
        lastTick = now
        if reduceMotion { head.snapToTarget() } else { head.step(dt) }
        applyHead()
        // Nothing moving: the clock stops until the pointer or a mood starts it again.
        if head.isSettled { clock.stop() }
    }

    private func applyHead() {
        withoutAnimation {
            // Art angles grow clockwise with y down; layers grow counter-clockwise with y up.
            headSpin.transform = CATransform3DMakeRotation(radians(-head.angle.value), 0, 0, 1)
            applyCrestRaise()
        }
    }

    private func applyCrestRaise() {
        let raised = allKept ? 14.0 : 0
        crest.transform = CATransform3DMakeRotation(radians(-head.crest.value + raised), 0, 0, 1)
    }

    private func refreshCount() {
        let showing = UserDefaults.standard.object(forKey: SettingsKey.showCount) as? Bool ?? true
        let text = showing && count > 0 ? String(min(count, 99)) : ""
        checkLayer.isHidden = !allKept
        countLayer.isHidden = allKept || text.isEmpty
        countLayer.contents = text.isEmpty ? nil : CompanionArt.countImage(text, colour: plumage.colourway.perched.eggText)
        // The bird is mirrored on the right edge; the number never is.
        countLayer.transform = mirrored ? CATransform3DMakeScale(-1, 1, 1) : CATransform3DIdentity
    }

    // MARK: Hit testing

    /// The resting silhouette at one pixel per art unit.
    private func makeHitMask() -> (data: [UInt8], width: Int)? {
        let width = 120
        var pixels = [UInt8](repeating: 0, count: width * width)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: width, bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return false }
            for name in ["perched-peg", "perched-legs", "perched-tail", "perched-body", "perched-wing", "perched-neck"] {
                if let image = CompanionArt.image(name, plumage: plumage, canvas: Self.canvas) {
                    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: width))
                }
            }
            return true
        }
        return drawn ? (pixels, width) : nil
    }

    func isHit(_ point: CGPoint) -> Bool {
        var x = (point.x - Self.windowSize.width / 2) / Self.scale + 60
        let y = (point.y - Self.windowSize.height / 2) / Self.scale + 60
        if mirrored { x = 120 - x }
        if mood == .tucked { x += Self.tuckPoints / Self.scale }
        // The head and egg move, so they count as generous circles around where they turn.
        if hypot(x - 81, y - 35) <= 24 || hypot(x - 52, y - 56) <= 14 { return true }
        guard let mask = hitMask else { return true }
        let reach = 4
        for dy in stride(from: -reach, through: reach, by: 2) {
            for dx in stride(from: -reach, through: reach, by: 2) {
                // The bitmap's first row is the top of the art, the same way up as y here.
                let px = Int(x) + dx, py = Int(y) + dy
                guard px >= 0, py >= 0, px < mask.width, py < mask.width else { continue }
                if mask.data[py * mask.width + px] > 40 { return true }
            }
        }
        return false
    }
}
