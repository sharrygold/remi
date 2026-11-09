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
                PebbleShape().fill(debug.colour.fill).frame(width: 68, height: 56)
            }
        }
        .frame(width: debug.prototype.windowSize.width, height: debug.prototype.windowSize.height)
        .accessibilityElement()
        .accessibilityLabel("\(AppInfo.displayName), \(count) tasks today")
        .accessibilityAddTraits(.isButton)
    }
}
