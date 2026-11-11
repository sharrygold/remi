import AppKit
import SwiftUI

/// The widget designs under comparison, switched live from the debug menu.
enum WidgetPrototype: String, CaseIterable, Identifiable {
    /// Raw values are stored in settings and placement keys, so they stay as they were.
    case bird, cord

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bird: "Perched"
        case .cord: "On the cord"
        }
    }

    var windowSize: CGSize {
        switch self {
        case .bird: CGSize(width: 104, height: 108)
        case .cord: CGSize(width: CordSimulation.width, height: 240)
        }
    }

    /// How far idle tucking slides the widget out of view.
    var tuckDistance: CGFloat {
        self == .cord ? 90 : windowSize.width * 0.45
    }
}

/// The widget's look and live state. Style and colour are chosen in Settings and remembered.
final class WidgetDebug: ObservableObject {

    @Published var prototype: WidgetPrototype {
        didSet { UserDefaults.standard.set(prototype.rawValue, forKey: CompanionKeys.style) }
    }
    @Published var plumage: Plumage {
        didSet { UserDefaults.standard.set(plumage.rawValue, forKey: CompanionKeys.plumage) }
    }

    /// Set by --preview-hover so hover states can be captured without a mouse.
    var previewHover = false
    /// Set by --preview-look=x,y so the bird's head turn can be captured without a mouse.
    var previewLook: CGPoint?
    /// The pointer in the bird's window coordinates (y down) while it is close enough to notice.
    @Published var birdPointer: CGPoint?
    @Published var onLeftEdge = false
    @Published var tucked = false {
        didSet {
            cord.tucked = tucked
            if !tucked { cord.wake() }
        }
    }
    let cord = CordSimulation()

    init(prototype: WidgetPrototype?, plumage: Plumage?) {
        let defaults = UserDefaults.standard
        // Anything unrecognised, such as the retired pebble, falls back to Perched.
        self.prototype = prototype ?? defaults.string(forKey: CompanionKeys.style).flatMap(WidgetPrototype.init) ?? .bird
        self.plumage = plumage ?? defaults.string(forKey: CompanionKeys.plumage).flatMap(Plumage.init) ?? .ivory
    }
}

/// Renders whichever prototype the debug menu has selected. Solid fills only; glass stays on the panel.
struct WidgetView: View {
    @ObservedObject var debug: WidgetDebug
    @ObservedObject var store: LibraryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(SettingsKey.showCount) private var showCount = true

    /// What the widget draws; hidden by the "Show today's task count" setting.
    private var count: Int { showCount ? store.todayOpenCount() : 0 }

    private var tuckOffset: CGSize {
        guard debug.tucked else { return .zero }
        let distance = debug.prototype.tuckDistance
        if debug.prototype == .cord { return CGSize(width: 0, height: -distance) }
        return CGSize(width: debug.onLeftEdge ? -distance : distance, height: 0)
    }

    var body: some View {
        Group {
            switch debug.prototype {
            case .bird:
                BirdWidget(colour: debug.plumage, count: count, target: debug.previewLook ?? debug.birdPointer, mirrored: debug.onLeftEdge)
            case .cord:
                CordWidget(colour: debug.plumage, count: count, simulation: debug.cord)
            }
        }
        .frame(width: debug.prototype.windowSize.width, height: debug.prototype.windowSize.height)
        .offset(tuckOffset)
        .animation(reduceMotion ? nil : Tokens.Motion.tuck, value: debug.tucked)
        .frame(width: debug.prototype.windowSize.width, height: debug.prototype.windowSize.height)
        .clipped()
        .accessibilityElement()
        .accessibilityLabel("\(AppInfo.displayName), \(store.todayOpenCount()) tasks today")
        .accessibilityAddTraits(.isButton)
    }
}

struct BirdBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 24, y: 50))
        path.addCurve(to: CGPoint(x: 44, y: 88), control1: CGPoint(x: 18, y: 72), control2: CGPoint(x: 28, y: 88))
        path.addCurve(to: CGPoint(x: 90, y: 78), control1: CGPoint(x: 62, y: 88), control2: CGPoint(x: 78, y: 84))
        path.addCurve(to: CGPoint(x: 62, y: 52), control1: CGPoint(x: 80, y: 68), control2: CGPoint(x: 72, y: 58))
        path.addCurve(to: CGPoint(x: 40, y: 38), control1: CGPoint(x: 54, y: 46), control2: CGPoint(x: 48, y: 38))
        path.addCurve(to: CGPoint(x: 24, y: 50), control1: CGPoint(x: 32, y: 38), control2: CGPoint(x: 26, y: 42))
        path.closeSubpath()
        return path
    }
}

/// A head with its beak pointing along +x, so one rotation aims it anywhere.
struct BirdHeadShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius: CGFloat = 13
        var path = Path()
        path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        path.move(to: CGPoint(x: center.x + radius - 3, y: center.y - 6))
        path.addLine(to: CGPoint(x: center.x + radius + 10, y: center.y))
        path.addLine(to: CGPoint(x: center.x + radius - 3, y: center.y + 6))
        path.closeSubpath()
        return path
    }
}

/// Sankofa-inspired: at rest it looks back at the egg on its back; on hover it looks at the pointer.
struct BirdWidget: View {
    let colour: Plumage
    let count: Int
    let target: CGPoint?
    let mirrored: Bool
    @State private var headAngle = lookingAtEgg
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let headCenter = CGPoint(x: 32, y: 32)
    private static let lookingAtEgg = 19.0
    private static let follow = Animation.interactiveSpring(response: 0.42, dampingFraction: 0.8)
    private static let settle = Animation.spring(response: 0.9, dampingFraction: 0.85)

    /// Angles run from the left, over the top, to the right. Below the bird the head holds still
    /// rather than whipping around through its own body.
    private func updateHead(_ target: CGPoint?) {
        guard let target else {
            headAngle = Self.lookingAtEgg
            return
        }
        let x = mirrored ? 104 - target.x : target.x
        var degrees = atan2(target.y - Self.headCenter.y, x - Self.headCenter.x) * 180 / .pi
        if degrees > 90 { degrees -= 360 }
        if degrees > 30 || degrees < -225 { return }
        headAngle = degrees
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(colour.body).frame(width: 56, height: 4).offset(x: 48, y: 92)
            ForEach([42.0, 54.0], id: \.self) { x in
                Rectangle().fill(colour.body).frame(width: 3, height: 10).offset(x: x, y: 84)
            }
            BirdBodyShape().fill(colour.body)
            Ellipse().fill(colour.accent).frame(width: 26, height: 32).offset(x: 59, y: 30)
            Text("\(count)").font(.caption.bold()).monospacedDigit().foregroundStyle(colour.body)
                .scaleEffect(x: mirrored ? -1 : 1)
                .frame(width: 26, height: 32).offset(x: 59, y: 30)
            head
                .frame(width: 60, height: 60)
                .rotationEffect(.degrees(headAngle))
                .offset(x: Self.headCenter.x - 30, y: Self.headCenter.y - 30)
                .animation(reduceMotion ? nil : (target == nil ? Self.settle : Self.follow), value: headAngle)
        }
        .frame(width: 104, height: 108, alignment: .topLeading)
        .scaleEffect(x: mirrored ? -1 : 1)
        .compositingGroup()
        .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
        .contentShape(Rectangle())
        .onAppear { updateHead(target) }
        .onChange(of: target) { _, new in updateHead(new) }
    }

    private var head: some View {
        ZStack {
            BirdHeadShape().fill(colour.body)
            Circle().fill(colour.accent).frame(width: 5, height: 5).offset(x: 5, y: -4)
        }
    }
}

/// A verlet rope pinned at the top. Pulling stretches it; letting go springs it back.
/// It falls asleep (no frames drawn at all) once settled and left alone, and wakes on any touch.
final class CordSimulation: ObservableObject {
    /// Seconds without a touch before the breeze fades and the rope may rest.
    static let restAfter: Double = 20
    @Published private(set) var asleep = false
    /// Set while the widget is tucked away, which lets the rope rest straight away.
    var tucked = false
    private var lastTouch: Double = 0
    private var breeze: CGFloat = 1
    static let width: CGFloat = 200
    static let pullToOpen: CGFloat = 24
    static let length: CGFloat = 152
    private static let maxKnots = 14
    private static let edgeMargin: CGFloat = 12
    private static let segments = 17
    private static let maxPull: CGFloat = 36
    private static let maxSideways: CGFloat = 30
    private static let hopStrength: CGFloat = 0.18
    private static let step: Double = 1.0 / 60
    private static let gravity: CGFloat = 900

    private(set) var points: [CGPoint] = []
    private var previous: [CGPoint] = []
    private(set) var length: CGFloat = 0
    private var span: CGFloat = 0
    private var target: CGPoint?
    private var lastDate: Date?
    private var leftover: Double = 0
    private var time: Double = 0
    var windEnabled = true

    var pin: CGPoint { CGPoint(x: Self.width / 2, y: 0) }
    var tip: CGPoint { points.last ?? pin }

    /// The cord is always the same length; knots share the space on it.
    func configure() {
        guard length == 0 else { return }
        length = Self.length
        span = length
        points = (0...Self.segments).map { CGPoint(x: pin.x, y: length * CGFloat($0) / CGFloat(Self.segments)) }
        previous = points
    }

    /// Any touch or nearby pointer: the breeze returns and frames resume.
    func wake() {
        lastTouch = time
        if asleep { asleep = false }
    }

    /// The largest movement in the last step, for the self-test.
    var largestMove: CGFloat {
        zip(points, previous).map { max(abs($0.x - $1.x), abs($0.y - $1.y)) }.max() ?? 0
    }
    var breezeLevel: CGFloat { breeze }
    var spanGap: CGFloat { span - length }

    /// True when nothing is moving enough to see.
    var isSettled: Bool {
        guard target == nil, abs(span - length) < 0.5 else { return false }
        return zip(points, previous).allSatisfy { abs($0.x - $1.x) < 0.01 && abs($0.y - $1.y) < 0.01 }
    }

    /// Follows the pointer by its travel since the press; y grows downward.
    func pull(dx: CGFloat, dy: CGFloat) {
        wake()
        target = CGPoint(x: pin.x + min(max(dx, -Self.maxSideways), Self.maxSideways),
                         y: length + min(max(dy, 0), Self.maxPull))
    }

    /// Lets go. Returns true when the pull went far enough to open the panel.
    @discardableResult
    func release() -> Bool {
        wake()
        guard let released = target else { return false }
        target = nil
        // Starting from rest stops the stretched rope flinging itself upward.
        previous = points
        // A pull stores a little energy, so the rope hops and swings before settling.
        let pulled = released.y - length
        for index in points.indices.dropFirst() {
            let along = CGFloat(index) / CGFloat(Self.segments)
            previous[index].y += pulled * Self.hopStrength * along
            previous[index].x -= pulled * 0.012 * along
        }
        return pulled >= Self.pullToOpen
    }

    /// A small push that builds along the rope, for a click.
    func nudge(_ speed: CGFloat = 1.2) {
        wake()
        for index in previous.indices {
            previous[index].x -= speed * CGFloat(index) / CGFloat(Self.segments)
        }
    }

    /// The pointer brushed the rope while moving by dx: only the part it touches is pushed.
    func brush(at point: CGPoint, dx: CGFloat) {
        wake()
        let push = min(max(dx, -6), 6) * 0.22
        for index in points.indices.dropFirst() {
            let distance = hypot(points[index].x - point.x, points[index].y - point.y)
            guard distance < 20 else { continue }
            previous[index].x -= push * (1 - distance / 20)
        }
    }

    /// The window slid sideways by dx; the rope lags behind it and swings back.
    func carry(dx: CGFloat) {
        wake()
        for index in points.indices.dropFirst() {
            let lag = dx * 0.5 * CGFloat(index) / CGFloat(Self.segments)
            points[index].x -= lag
            previous[index].x -= lag
        }
    }

    /// True when a point in window coordinates (y down) is close enough to grab the rope.
    func isNear(_ point: CGPoint, within reach: CGFloat = 14) -> Bool {
        points.contains { hypot($0.x - point.x, $0.y - point.y) <= reach + span / CGFloat(Self.segments) / 2 }
    }

    func advance(to date: Date) {
        defer { lastDate = date }
        guard let lastDate else { return }
        leftover += min(date.timeIntervalSince(lastDate), 0.1)
        while leftover >= Self.step {
            stepOnce()
            leftover -= Self.step
        }
        if !asleep, breeze < 0.001, isSettled {
            // Published outside the view update that called this.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.breeze < 0.001, self.isSettled else { return }
                self.asleep = true
            }
        }
    }

    func stepOnce() {
        time += Self.step
        let dt2 = CGFloat(Self.step * Self.step)
        // The breeze fades out when left alone (or tucked) and fades back in on a touch.
        let resting = tucked || time - lastTouch > Self.restAfter
        breeze += ((resting ? 0 : 1) - breeze) * 0.02
        if breeze < 0.001 { breeze = 0 }
        let wind = windEnabled ? CGFloat(sin(time * 1.1) * 24 + sin(time * 0.37) * 12) * breeze : 0
        if target == nil { span += (length - span) * 0.12 }
        let settling = target == nil && span > length + 0.5
        let damping: CGFloat = settling ? 0.97 : 0.98
        for index in points.indices.dropFirst() {
            let velocity = CGPoint(x: (points[index].x - previous[index].x) * damping,
                                   y: (points[index].y - previous[index].y) * damping)
            previous[index] = points[index]
            points[index].x += velocity.x + wind * dt2
            points[index].y += velocity.y + Self.gravity * dt2
        }
        if let target { span = max(length, hypot(target.x - pin.x, target.y - pin.y)) }
        let segment = span / CGFloat(Self.segments)
        for _ in 0..<24 {
            points[0] = pin
            if let target { points[Self.segments] = target }
            for index in 0..<Self.segments {
                let a = points[index], b = points[index + 1]
                let distance = max(hypot(b.x - a.x, b.y - a.y), 0.0001)
                // A rope resists stretching but can go slack, which is what lets it hop.
                if target == nil && distance <= segment { continue }
                let correction = (distance - segment) / distance / 2
                let shift = CGPoint(x: (b.x - a.x) * correction, y: (b.y - a.y) * correction)
                if index > 0 { points[index] = CGPoint(x: a.x + shift.x, y: a.y + shift.y) }
                if index + 1 < Self.segments || target == nil {
                    let doubled: CGFloat = index == 0 ? 2 : 1
                    points[index + 1] = CGPoint(x: b.x - shift.x * doubled, y: b.y - shift.y * doubled)
                }
            }
        }
        for index in points.indices {
            points[index].x = min(max(points[index].x, Self.edgeMargin), Self.width - Self.edgeMargin)
        }
    }

    /// Knots spaced along the lower part of the rope, however many there are.
    func knots(count: Int) -> [CGPoint] {
        let shown = min(count, Self.maxKnots)
        guard shown > 0, points.count > Self.segments else { return [] }
        let first = Double(Self.segments) * 0.3
        let last = Double(Self.segments)
        return (0..<shown).map { index in
            let position = shown == 1 ? last : first + (last - first) * Double(index) / Double(shown - 1)
            let lower = min(Int(position), Self.segments - 1)
            let t = CGFloat(position - Double(lower))
            let a = points[lower], b = points[lower + 1]
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
    }

    func knotRadius(count: Int) -> CGFloat {
        let shown = min(count, Self.maxKnots)
        guard shown > 1 else { return 7 }
        let spacing = length * 0.7 / CGFloat(shown - 1)
        return min(7, spacing * 0.45)
    }
}

/// One knot per task due today. Sways on its own and opens the panel when pulled.
struct CordWidget: View {
    let colour: Plumage
    let count: Int
    @ObservedObject var simulation: CordSimulation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Paused while asleep, so a resting cord costs nothing.
        TimelineView(.animation(paused: simulation.asleep)) { context in
            Canvas { canvas, _ in
                simulation.windEnabled = !reduceMotion
                simulation.advance(to: context.date)
                let points = simulation.points
                guard let first = points.first else { return }
                canvas.addFilter(.shadow(color: .black.opacity(0.25), radius: 3, y: 2))
                var rope = Path()
                rope.move(to: first)
                points.dropFirst().forEach { rope.addLine(to: $0) }
                canvas.stroke(rope, with: .color(colour.body), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                let radius = simulation.knotRadius(count: count)
                for point in simulation.knots(count: count) {
                    canvas.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                                with: .color(colour.body))
                }
            }
        }
        .onAppear { simulation.configure() }
    }
}
