import AppKit

/// Where a widget sits on one display, as fractions so it survives resolution changes.
struct WidgetPlacement: Codable, Equatable {
    /// Side widgets only: which edge it is snapped to.
    var onLeftEdge: Bool
    /// Along the edge, 0 to 1: bottom to top on the sides, left to right along the top.
    var fraction: CGFloat

    static func standard(for prototype: WidgetPrototype) -> WidgetPlacement {
        prototype == .cord ? WidgetPlacement(onLeftEdge: false, fraction: 0.9) : WidgetPlacement(onLeftEdge: false, fraction: 2.0 / 3.0)
    }

    func frame(for prototype: WidgetPrototype, on visible: NSRect) -> NSRect {
        let size = prototype.windowSize
        if prototype == .cord {
            return NSRect(x: visible.minX + fraction * (visible.width - size.width), y: visible.maxY - size.height,
                          width: size.width, height: size.height)
        }
        return NSRect(x: onLeftEdge ? visible.minX : visible.maxX - size.width,
                      y: visible.minY + fraction * (visible.height - size.height),
                      width: size.width, height: size.height)
    }

    /// The placement nearest to a window frame, which is what snapping means.
    static func nearest(to frame: NSRect, prototype: WidgetPrototype, on visible: NSRect) -> WidgetPlacement {
        func clamp(_ value: CGFloat) -> CGFloat { min(max(value, 0), 1) }
        if prototype == .cord {
            return WidgetPlacement(onLeftEdge: false, fraction: clamp((frame.minX - visible.minX) / (visible.width - frame.width)))
        }
        return WidgetPlacement(onLeftEdge: frame.midX < visible.midX,
                               fraction: clamp((frame.minY - visible.minY) / (visible.height - frame.height)))
    }
}

/// Remembers each widget's position per display, keyed by the display's stable ID.
enum PlacementStore {
    private static func key(_ prototype: WidgetPrototype, _ display: String) -> String { "placement.\(prototype.rawValue).\(display)" }
    private static func lastKey(_ prototype: WidgetPrototype) -> String { "placement.\(prototype.rawValue).lastDisplay" }

    static func displayID(of screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() else { return "unknown" }
        return CFUUIDCreateString(nil, uuid) as String
    }

    static func save(_ placement: WidgetPlacement, prototype: WidgetPrototype, on screen: NSScreen) {
        let display = displayID(of: screen)
        if let data = try? JSONEncoder().encode(placement) {
            UserDefaults.standard.set(data, forKey: key(prototype, display))
        }
        UserDefaults.standard.set(display, forKey: lastKey(prototype))
    }

    static func load(prototype: WidgetPrototype, on screen: NSScreen) -> WidgetPlacement? {
        guard let data = UserDefaults.standard.data(forKey: key(prototype, displayID(of: screen))) else { return nil }
        return try? JSONDecoder().decode(WidgetPlacement.self, from: data)
    }

    /// The display it was last on if still connected, otherwise the main display.
    static func preferredScreen(for prototype: WidgetPrototype) -> NSScreen {
        let last = UserDefaults.standard.string(forKey: lastKey(prototype))
        return NSScreen.screens.first { displayID(of: $0) == last } ?? NSScreen.screens[0]
    }

    static func clear(prototype: WidgetPrototype, on screen: NSScreen) {
        UserDefaults.standard.removeObject(forKey: key(prototype, displayID(of: screen)))
        UserDefaults.standard.removeObject(forKey: lastKey(prototype))
    }
}
