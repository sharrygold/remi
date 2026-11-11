import CoreGraphics
import Foundation

/// A damped spring advanced frame by frame, so it can be retargeted midway without a jump.
struct Spring {
    var value: Double
    var velocity = 0.0
    var target: Double
    var omega: Double
    var damping: Double

    init(_ value: Double, response: Double = 0.45, damping: Double = 1) {
        self.value = value
        target = value
        omega = 2 * .pi / response
        self.damping = damping
    }

    mutating func retune(response: Double, damping: Double) {
        omega = 2 * .pi / response
        self.damping = damping
    }

    mutating func step(_ dt: Double) {
        var left = dt
        while left > 0 {
            let h = min(left, 1.0 / 480)
            velocity += (omega * omega * (target - value) - 2 * damping * omega * velocity) * h
            value += velocity * h
            left -= h
        }
    }

    mutating func snap() {
        value = target
        velocity = 0
    }

    var isSettled: Bool { abs(value - target) < 0.02 && abs(velocity) < 0.05 }
}

/// The perched bird's head, following the brand spec's pseudocode. Angles are in the 120-unit art
/// space with y down: 0 faces along +x, and the head never turns through the body (40–140°).
struct HeadFollow {
    static let pivot = CGPoint(x: 81, y: 35)
    static let restT = 6.0
    static let facingT = 220.0
    static let workingT = 214.0
    static let freeArc = 260.0
    private static let followOmega = 120.0.squareRoot()
    private static let returnOmega = 5 / 0.6

    private(set) var t = restT
    private(set) var angle = Spring(140 + restT)
    private(set) var crest = Spring(0, response: 0.5, damping: 0.45)
    private var gliding = false

    init() { angle.omega = Self.followOmega }

    /// Where along the free arc a pointer sits, waiting at the nearest edge when it is behind the body.
    static func arcPosition(for pointer: CGPoint, previous: Double) -> Double {
        var a = atan2(pointer.y - pivot.y, pointer.x - pivot.x) * 180 / .pi
        if a < 0 { a += 360 }
        let t = (a - 140 + 360).truncatingRemainder(dividingBy: 360)
        return t > freeArc ? (previous < 130 ? 0 : freeArc) : t
    }

    /// How long a swing of this many degrees should take.
    static func swingDuration(for jump: Double) -> Double {
        jump > 40 ? min(0.9, 0.3 + jump / 400) : 0.24
    }

    mutating func aim(at pointer: CGPoint) {
        move(to: Self.arcPosition(for: pointer, previous: t))
    }

    /// A chosen spot on the arc (rest, facing the panel). `returning` uses the slower 0.6 s settle.
    mutating func move(to next: Double, returning: Bool = false) {
        let delta = next - t
        crest.value = min(max(-delta * 0.8, -22), 22)
        t = next
        angle.target = 140 + next
        let jump = abs(angle.target - angle.value)
        if returning {
            angle.omega = Self.returnOmega
            gliding = true
        } else if jump > 40 {
            angle.omega = 5 / Self.swingDuration(for: jump)
            gliding = true
        } else if !gliding {
            angle.omega = Self.followOmega
        }
    }

    mutating func step(_ dt: Double) {
        angle.step(dt)
        crest.step(dt)
        if gliding, abs(angle.target - angle.value) < 8 {
            gliding = false
            angle.omega = Self.followOmega
        }
    }

    mutating func snapToTarget() {
        angle.snap()
        crest.snap()
    }

    var isSettled: Bool { angle.isSettled && crest.isSettled }
}

/// What a frame of the cord should look like, in 120-unit art space.
struct CordFrame {
    var pull = 0.0
    var sway = 0.0
    var lean = 0.0
    var rock = 0.0
    var squat = 0.0
    var hop = 0.0
    var bob = 0.0
    var tilt = 0.0
    var puff = 1.0
    var breath = 1.0
    var eyesClosed = false
}

/// The cord's state machine: four states plus short one-shots, all driven by per-frame springs.
/// It takes the clock as an argument, so its behaviour can be tested without a screen.
final class CordMotion {
    enum State { case tucked, lowered, pulling, panelOpen }
    enum Event { case taskAdded, linkCaught, taskDone, allDone, stretch, release, click }

    static let tuckedPull = -128.0
    static let maxPull = 56.0
    static let openThreshold = 14.0
    static let awayDelay = 1.2
    static let dozeAfter = 20.0

    private(set) var state = State.tucked
    var reduceMotion = false
    /// Off when "Tuck into the edge when idle" is off: the cord then stays down and dozes.
    var autoTuck = true

    private var pull = Spring(tuckedPull, response: 0.5, damping: 0.9)
    private var lean = Spring(0, response: 0.7, damping: 0.45)
    private var squat = Spring(0, response: 0.25, damping: 1)
    private var look = Spring(0, response: 0.4, damping: 1)
    private var awake = Spring(0, response: 0.8, damping: 1)
    private var lastNear = -Double.infinity
    private var isNear = false
    private var holdUntil = -Double.infinity
    private var shots: [Event: Double] = [:]
    private var nextBlink = 0.0
    private var blinkEnds = -Double.infinity
    private var clock = 0.0

    /// Where the pull is headed; a view uses this to spot a jump it should fade through.
    var pullTarget: Double { pull.target }

    private func lowerSpring() { pull.retune(response: 0.45, damping: 0.55) }
    private func tuckSpring() { pull.retune(response: 0.55, damping: 0.92) }

    /// True when the pointer is close enough for the cord to notice.
    func pointer(near: Bool, now: Double) {
        // The moment it leaves counts as the last time it was near.
        if near || isNear { lastNear = now }
        isNear = near
        if near, state == .tucked { lower() }
    }

    /// Radians-free head tilt toward the pointer; zero when it has gone.
    func look(toward degrees: Double) { look.target = min(max(degrees, -8), 8) }

    private func lower() {
        state = .lowered
        lowerSpring()
        pull.target = 0
    }

    func setPanelOpen(_ open: Bool, now: Double) {
        if open {
            state = .panelOpen
            lowerSpring()
            pull.target = 0
        } else if state == .panelOpen {
            state = .lowered
            lastNear = now
        }
    }

    func startPull() {
        state = .pulling
        pull.retune(response: 0.08, damping: 1)
        pull.target = max(pull.value, 0)
        squat.target = 1
    }

    /// Follows the finger; past the limit it stops.
    func drag(by amount: Double) {
        guard state == .pulling else { return }
        pull.target = min(max(amount, 0), Self.maxPull)
    }

    /// Lets go. Returns true when the pull went far enough to open the panel.
    func release(now: Double) -> Bool {
        guard state == .pulling else { return false }
        let opens = pull.target >= Self.openThreshold
        state = .lowered
        lastNear = now
        lowerSpring()
        pull.target = 0
        squat.target = 0
        fire(.release, now: now)
        return opens
    }

    /// The window moved sideways: the cord trails behind and swings back.
    func carry(dx: Double, now: Double) {
        lastNear = now
        guard !reduceMotion else { return }
        lean.value = min(max(lean.value + dx * 0.35, -8), 8)
    }

    func fire(_ event: Event, now: Double) {
        shots[event] = now
        // Anything Remi does should be seen, so the cord comes down first and stays a moment.
        switch event {
        case .taskAdded, .linkCaught, .stretch, .taskDone, .allDone:
            holdUntil = max(holdUntil, now + (event == .stretch ? 1.9 : 1.5))
            if state == .tucked { lower() }
        case .release, .click:
            break
        }
    }

    private func age(_ event: Event, now: Double) -> Double? {
        guard let start = shots[event] else { return nil }
        let age = now - start
        return age >= 0 ? age : nil
    }

    private static let shotLengths: [Event: Double] = [
        .taskAdded: 0.8, .linkCaught: 0.5, .taskDone: 0.5, .allDone: 0.7, .stretch: 1.3, .release: 1.6, .click: 0.6,
    ]

    private var shotsRunning: Bool { !shots.isEmpty }

    /// The release rock: +9, -7, +4, -2, 0 over 1.6 s.
    private static func releaseRock(_ t: Double) -> Double {
        let times = [0, 0.2, 0.55, 0.9, 1.25, 1.6]
        let values = [0.0, 9, -7, 4, -2, 0]
        guard t < 1.6, let i = times.lastIndex(where: { $0 <= t }), i + 1 < times.count else { return 0 }
        let f = (t - times[i]) / (times[i + 1] - times[i])
        return values[i] + (values[i + 1] - values[i]) * (0.5 - 0.5 * cos(.pi * f))
    }

    func tick(now: Double, dt: Double) -> CordFrame {
        clock = now
        if state == .lowered, autoTuck, now >= holdUntil, !isNear, now - lastNear >= Self.awayDelay {
            state = .tucked
            tuckSpring()
            pull.target = Self.tuckedPull
        }
        let dozing = state == .tucked || (state == .lowered && !autoTuck && !isNear && now - lastNear >= Self.dozeAfter && now >= holdUntil)
        awake.target = dozing ? 0 : 1
        for (event, start) in shots where now - start > (Self.shotLengths[event] ?? 1) { shots[event] = nil }

        var frame = CordFrame()
        if reduceMotion {
            pull.snap(); squat.snap(); look.snap(); awake.snap(); lean.snap()
        } else {
            pull.step(dt); lean.step(dt); squat.step(dt); look.step(dt); awake.step(dt)
        }
        frame.pull = pull.value
        frame.lean = lean.value
        frame.squat = squat.value
        frame.eyesClosed = dozing || now < blinkEnds
        guard !reduceMotion else {
            frame.tilt = look.value
            return frame
        }

        let alive = max(awake.value, 0)
        frame.sway = alive * 1.2 * sin(2 * .pi * now / 6)
        frame.rock = alive * (1 - squat.value) * 2.5 * sin(2 * .pi * now / 3.2)
        frame.breath = 1 + alive * 0.012 * sin(2 * .pi * now / (dozing ? 7 : 4.5))
        frame.tilt = look.value
        if state == .panelOpen { frame.bob = 0.7 * sin(2 * .pi * now / 2.2) }

        if let t = age(.release, now: now) {
            frame.rock += Self.releaseRock(t)
            if t < 0.4 { frame.hop += 7 * sin(.pi * t / 0.4) }
        }
        if let t = age(.taskAdded, now: now) {
            if t < 0.45 { frame.hop += 5 * sin(.pi * t / 0.45) }
            if t < 0.8 { frame.rock += 3.5 * sin(2 * .pi * t / 0.4) * (1 - t / 0.8) }
        }
        if let t = age(.linkCaught, now: now), t < 0.5 { frame.tilt += -9 * sin(.pi * t / 0.5) }
        if let t = age(.taskDone, now: now), t < 0.5 { frame.tilt += 4 * sin(.pi * t / 0.5) }
        if let t = age(.click, now: now), t < 0.6 { frame.rock += 3 * sin(2 * .pi * t / 0.6) * (1 - t / 0.6) }
        if let t = age(.allDone, now: now), t < 0.7 { frame.puff = 1 + 0.08 * sin(.pi * t / 0.7) }
        if let t = age(.stretch, now: now), t > 0.4, t < 1.3 { frame.tilt += 4 * sin(2 * .pi * 3 * (t - 0.4) / 0.9) }

        // Blink only while awake and looking about.
        if !dozing, now >= nextBlink {
            blinkEnds = now + 0.13
            nextBlink = now + Double.random(in: 3...6)
        }
        return frame
    }

    /// Nothing left to draw until something touches it, so the frame clock can stop.
    var isAtRest: Bool {
        guard !shotsRunning, pull.isSettled, lean.isSettled, squat.isSettled else { return false }
        let dozing = state == .tucked || (state == .lowered && !autoTuck && !isNear && clock - lastNear >= Self.dozeAfter && clock >= holdUntil)
        return dozing && awake.value < 0.01
    }
}
