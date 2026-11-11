import Foundation

/// The panel's accent, which follows the Plumage setting and the light or dark panel.
enum BrandAccent {
    static let jet = "#121110"

    static func hex(plumage: String, dark: Bool) -> String {
        switch plumage {
        case "jet": dark ? "#C9A25A" : "#24211E"
        case "oxblood": dark ? "#D8B56A" : "#7A2A2E"
        case "brass": "#C9A25A"
        default: dark ? "#F2ECE0" : "#C9A25A" // Ivory is unreadable on a light panel, so it turns gold.
        }
    }

    /// Text to set on an accent fill: whichever of jet or white reads better.
    static func onAccent(_ accent: String) -> String {
        contrast(accent, jet) >= contrast(accent, "#FFFFFF") ? jet : "#FFFFFF"
    }

    /// WCAG contrast ratio between two "#RRGGBB" colours.
    static func contrast(_ a: String, _ b: String) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    private static func luminance(_ hex: String) -> Double {
        let value = Int(hex.dropFirst(), radix: 16) ?? 0
        let channels = [(value >> 16) & 255, (value >> 8) & 255, value & 255].map { channel -> Double in
            let c = Double(channel) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }
}
