import AppKit
import SwiftUI

/// Colours under comparison in the debug menu. `ink` stays readable on `fill`.
enum WidgetColour: String, CaseIterable, Identifiable {
    case stone, offWhite, charcoal, terracotta, accent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stone: "Warm stone grey"
        case .offWhite: "Off-white"
        case .charcoal: "Deep charcoal"
        case .terracotta: "Muted terracotta"
        case .accent: "System accent"
        }
    }

    var fill: Color {
        switch self {
        case .stone: Color(red: 0.62, green: 0.58, blue: 0.53)
        case .offWhite: Color(red: 0.96, green: 0.94, blue: 0.90)
        case .charcoal: Color(red: 0.17, green: 0.17, blue: 0.18)
        case .terracotta: Color(red: 0.72, green: 0.42, blue: 0.32)
        case .accent: .accentColor
        }
    }

    var ink: Color {
        switch self {
        case .offWhite: Color(red: 0.17, green: 0.17, blue: 0.18)
        default: Color(red: 0.98, green: 0.97, blue: 0.95)
        }
    }
}

/// The widget designs under comparison, switched live from the debug menu.
enum WidgetPrototype: String, CaseIterable, Identifiable {
    case pebble, bird, cord

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pebble: "Pebble"
        case .bird: "Sankofa bird"
        case .cord: "Knotted cord"
        }
    }

    var windowSize: CGSize {
        switch self {
        case .pebble: CGSize(width: 96, height: 88)
        case .bird: CGSize(width: 104, height: 108)
        case .cord: CGSize(width: CordSimulation.width, height: 240)
        }
    }

    /// Where the widget starts on a display's visible area, in AppKit coordinates.
    func origin(in visible: NSRect) -> NSPoint {
        switch self {
        case .cord:
            NSPoint(x: visible.maxX - windowSize.width - 40, y: visible.maxY - windowSize.height)
        case .pebble, .bird:
            NSPoint(x: visible.maxX - windowSize.width, y: visible.maxY - visible.height / 3 - windowSize.height / 2)
        }
    }
}

/// Live debug choices, remembered between launches.
final class WidgetDebug: ObservableObject {
    private static let prototypeKey = "debug.widgetPrototype"
    private static let colourKey = "debug.widgetColour"

    @Published var prototype: WidgetPrototype {
        didSet { UserDefaults.standard.set(prototype.rawValue, forKey: Self.prototypeKey) }
    }
    @Published var colour: WidgetColour {
        didSet { UserDefaults.standard.set(colour.rawValue, forKey: Self.colourKey) }
    }

    /// Set by --preview-hover so hover states can be captured without a mouse.
    var previewHover = false
    /// Set by --preview-look=x,y so the bird's head turn can be captured without a mouse.
    var previewLook: CGPoint?
    let cord = CordSimulation()

    init(prototype: WidgetPrototype?, colour: WidgetColour?) {
        let defaults = UserDefaults.standard
        self.prototype = prototype ?? defaults.string(forKey: Self.prototypeKey).flatMap(WidgetPrototype.init) ?? .bird
        self.colour = colour ?? defaults.string(forKey: Self.colourKey).flatMap(WidgetColour.init) ?? .stone
    }
}

/// Renders whichever prototype the debug menu has selected. Solid fills only; glass stays on the panel.
struct WidgetView: View {
    @ObservedObject var debug: WidgetDebug
    let count: Int

    var body: some View {
        Group {
            switch debug.prototype {
            case .pebble:
                PebbleWidget(colour: debug.colour, count: count, previewHover: debug.previewHover)
            case .bird:
                BirdWidget(colour: debug.colour, count: count, previewLook: debug.previewLook)
            case .cord:
                CordWidget(colour: debug.colour, count: count, simulation: debug.cord)
            }
        }
        .frame(width: debug.prototype.windowSize.width, height: debug.prototype.windowSize.height)
        .accessibilityElement()
        .accessibilityLabel("\(AppInfo.displayName), \(count) tasks today")
        .accessibilityAddTraits(.isButton)
    }
}

/// A solid stone that breathes slowly and perks up under the pointer.
struct PebbleWidget: View {
    let colour: WidgetColour
    let count: Int
    let previewHover: Bool
    @State private var hovering = false
    @State private var inhaled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var perked: Bool { hovering || previewHover }

    var body: some View {
        PebbleShape()
            .fill(colour.fill)
            .overlay {
                VStack(spacing: 1) {
                    HStack(spacing: Tokens.Spacing.m) {
                        eye
                        eye
                    }
                    Text("\(count)").font(.headline).monospacedDigit()
                }
                .foregroundStyle(colour.ink)
                .offset(y: perked ? -1 : 0)
            }
            .frame(width: 68, height: 56)
            .shadow(color: .black.opacity(perked ? 0.32 : 0.24), radius: perked ? 8 : 5, y: perked ? 5 : 3)
            .scaleEffect(x: inhaled ? 1.02 : 0.99, y: inhaled ? 0.98 : 1.02, anchor: .bottom)
            .scaleEffect(perked && !reduceMotion ? 1.08 : 1)
            .rotationEffect(.degrees(perked && !reduceMotion ? -4 : 0))
            .animation(reduceMotion ? nil : Tokens.Motion.quick, value: perked)
            .onHover { hovering = $0 }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { inhaled = true }
            }
    }

    private var eye: some View {
        Capsule().frame(width: 4, height: perked ? 10 : 7)
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
    let colour: WidgetColour
    let count: Int
    let previewLook: CGPoint?
    @State private var pointer: CGPoint?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let headCenter = CGPoint(x: 32, y: 32)
    private static let lookingAtEgg = 19.0

    /// Angles run from the left, over the top, to the right, so the head never turns through the body.
    private var headAngle: Double {
        guard let target = previewLook ?? pointer else { return Self.lookingAtEgg }
        var degrees = atan2(target.y - Self.headCenter.y, target.x - Self.headCenter.x) * 180 / .pi
        if degrees > 90 { degrees -= 360 }
        return min(max(degrees, -225), 30)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(colour.fill).frame(width: 56, height: 4).offset(x: 48, y: 92)
            ForEach([42.0, 54.0], id: \.self) { x in
                Rectangle().fill(colour.fill).frame(width: 3, height: 10).offset(x: x, y: 84)
            }
            BirdBodyShape().fill(colour.fill)
            Ellipse().fill(colour.ink).frame(width: 26, height: 32).offset(x: 59, y: 30)
            Text("\(count)").font(.caption.bold()).monospacedDigit().foregroundStyle(colour.fill)
                .frame(width: 26, height: 32).offset(x: 59, y: 30)
            head
                .frame(width: 60, height: 60)
                .rotationEffect(.degrees(headAngle))
                .offset(x: Self.headCenter.x - 30, y: Self.headCenter.y - 30)
                .animation(reduceMotion ? nil : .interactiveSpring(response: 0.3, dampingFraction: 0.72), value: headAngle)
        }
        .frame(width: 104, height: 108, alignment: .topLeading)
        .compositingGroup()
        .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
        .contentShape(Rectangle())
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location): pointer = location
            case .ended: pointer = nil
            }
        }
    }

    private var head: some View {
        ZStack {
            BirdHeadShape().fill(colour.fill)
            Circle().fill(colour.ink).frame(width: 5, height: 5).offset(x: 5, y: -4)
        }
    }
}

/// A verlet rope pinned at the top. Pulling stretches it; letting go springs it back.
final class CordSimulation {
    static let width: CGFloat = 200
    static let pullToOpen: CGFloat = 24
    static let length: CGFloat = 152
    private static let maxKnots = 14
    private static let edgeMargin: CGFloat = 12
    private static let segments = 17
    private static let maxPull: CGFloat = 36
    private static let maxSideways: CGFloat = 30
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

    /// Follows the pointer by its travel since the press; y grows downward.
    func pull(dx: CGFloat, dy: CGFloat) {
        target = CGPoint(x: pin.x + min(max(dx, -Self.maxSideways), Self.maxSideways),
                         y: length + min(max(dy, 0), Self.maxPull))
    }

    /// Lets go. Returns true when the pull went far enough to open the panel.
    @discardableResult
    func release() -> Bool {
        guard let released = target else { return false }
        target = nil
        // Starting from rest stops the stretched rope flinging itself upward.
        previous = points
        return released.y - length >= Self.pullToOpen
    }

    /// A small push that builds along the rope, for a click.
    func nudge(_ speed: CGFloat = 1.2) {
        for index in previous.indices {
            previous[index].x -= speed * CGFloat(index) / CGFloat(Self.segments)
        }
    }

    /// The window slid sideways by dx; the rope lags behind it and swings back.
    func carry(dx: CGFloat) {
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
    }

    func stepOnce() {
        time += Self.step
        let dt2 = CGFloat(Self.step * Self.step)
        let wind = windEnabled ? CGFloat(sin(time * 1.1) * 24 + sin(time * 0.37) * 12) : 0
        if target == nil { span += (length - span) * 0.12 }
        let settling = target == nil && span > length + 0.5
        let damping: CGFloat = settling ? 0.7 : 0.98
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
    let colour: WidgetColour
    let count: Int
    let simulation: CordSimulation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { canvas, _ in
                simulation.windEnabled = !reduceMotion
                simulation.advance(to: context.date)
                let points = simulation.points
                guard let first = points.first else { return }
                canvas.addFilter(.shadow(color: .black.opacity(0.25), radius: 3, y: 2))
                var rope = Path()
                rope.move(to: first)
                points.dropFirst().forEach { rope.addLine(to: $0) }
                canvas.stroke(rope, with: .color(colour.fill), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                let radius = simulation.knotRadius(count: count)
                for point in simulation.knots(count: count) {
                    canvas.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                                with: .color(colour.fill))
                }
            }
        }
        .onAppear { simulation.configure() }
    }
}
