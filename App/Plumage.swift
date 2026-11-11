import AppKit
import SwiftUI

/// The companion colour setting. Each colourway recolours the perched bird, the cord and Remi on
/// the cord together. The values live in Resources/plumage.json, copied from the brand kit.
enum Plumage: String, CaseIterable, Identifiable {
    case ivory, jet, oxblood, brass

    var id: String { rawValue }

    struct Perched: Decodable {
        let body, feather, stitch, wingSatin, egg, eggText, beak, crest, eye, metal, halo: String
    }

    struct Cord: Decodable {
        let body, egg, beak, metal, braidA, braidB, knot: String
    }

    struct Colourway: Decodable {
        let name, note: String
        let cord: Cord
        let perched: Perched
    }

    private struct File: Decodable {
        let colourways: [String: Colourway]
    }

    private static let all: [String: Colourway] = {
        guard let url = Bundle.main.url(forResource: "plumage", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else {
            fatalError("plumage.json is missing from the app bundle")
        }
        return file.colourways
    }()

    var colourway: Colourway {
        guard let value = Self.all[rawValue] else { fatalError("plumage.json has no \(rawValue)") }
        return value
    }

    var title: String { colourway.name }
    var body: Color { Color(hex: colourway.perched.body) }
    var accent: Color { Color(hex: colourway.perched.egg) }
}

extension NSColor {
    private static var currentPlumage: String {
        UserDefaults.standard.string(forKey: CompanionKeys.plumage) ?? Plumage.ivory.rawValue
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// The panel's accent. Set once here and read everywhere; it follows Plumage and light or dark.
    static let brand = NSColor(name: "brandAccent") { appearance in
        NSColor(hex: BrandAccent.hex(plumage: currentPlumage, dark: isDark(appearance)))
    }

    /// Text on a brand fill, always at least 4.5:1.
    static let onBrand = NSColor(name: "onBrandAccent") { appearance in
        NSColor(hex: BrandAccent.onAccent(BrandAccent.hex(plumage: currentPlumage, dark: isDark(appearance))))
    }

    /// "#RRGGBB"
    convenience init(hex: String) {
        let value = Int(hex.dropFirst(), radix: 16) ?? 0
        self.init(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255,
                  blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}

extension Color {
    init(hex: String) { self.init(nsColor: NSColor(hex: hex)) }
    static let brand = Color(nsColor: .brand)
    static let onBrand = Color(nsColor: .onBrand)
}

extension View {
    /// Text fields paint their selection in the tint, so a full-strength ivory would hide the white text.
    func brandTextInput() -> some View { tint(Color.brand.opacity(0.3)) }
}
