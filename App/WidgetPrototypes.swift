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
    case pebble, bird

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pebble: "Pebble"
        case .bird: "Sankofa bird"
        }
    }

    var windowSize: CGSize {
        switch self {
        case .pebble: CGSize(width: 96, height: 88)
        case .bird: CGSize(width: 104, height: 108)
        }
    }

    /// Where the widget starts on a display's visible area, in AppKit coordinates.
    func origin(in visible: NSRect) -> NSPoint {
        switch self {
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

    init(prototype: WidgetPrototype?, colour: WidgetColour?) {
        let defaults = UserDefaults.standard
        self.prototype = prototype ?? defaults.string(forKey: Self.prototypeKey).flatMap(WidgetPrototype.init) ?? .pebble
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
