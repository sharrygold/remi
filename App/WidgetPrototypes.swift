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
    case pebble

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pebble: "Pebble"
        }
    }

    var windowSize: CGSize {
        switch self {
        case .pebble: CGSize(width: 96, height: 88)
        }
    }

    /// Where the widget starts on a display's visible area, in AppKit coordinates.
    func origin(in visible: NSRect) -> NSPoint {
        switch self {
        case .pebble:
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
