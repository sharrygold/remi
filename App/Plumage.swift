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
    /// "#RRGGBB"
    convenience init(hex: String) {
        let value = Int(hex.dropFirst(), radix: 16) ?? 0
        self.init(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255,
                  blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}

extension Color {
    init(hex: String) { self.init(nsColor: NSColor(hex: hex)) }
}
