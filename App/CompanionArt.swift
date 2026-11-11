import AppKit
import CoreText

/// Turns the recolourable SVG layers into finished bitmaps, once per colourway. Animating finished
/// layers keeps every stitch locked in place: nothing is ever re-stroked while it moves.
enum CompanionArt {
    static let pixelsPerUnit: CGFloat = 3
    private static var cache: [String: CGImage] = [:]

    static func image(_ layer: String, plumage: Plumage, canvas: CGSize) -> CGImage? {
        let key = "\(layer)/\(plumage.rawValue)"
        if let cached = cache[key] { return cached }
        guard let url = Bundle.main.url(forResource: layer, withExtension: "svg"),
              var text = try? String(contentsOf: url, encoding: .utf8) else {
            NSLog("Missing companion layer \(layer)")
            return nil
        }
        for (token, hex) in tokens(for: layer, plumage: plumage) { text = text.replacingOccurrences(of: "{{\(token)}}", with: hex) }
        guard let svg = NSImage(data: Data(text.utf8)) else { return nil }
        let width = Int(canvas.width * pixelsPerUnit), height = Int(canvas.height * pixelsPerUnit)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        svg.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        let image = context.makeImage()
        cache[key] = image
        return image
    }

    private static func tokens(for layer: String, plumage: Plumage) -> [String: String] {
        let way = plumage.colourway
        if layer.hasPrefix("cord") {
            let c = way.cord
            return ["body": c.body, "egg": c.egg, "beak": c.beak, "metal": c.metal, "braidA": c.braidA, "braidB": c.braidB, "knot": c.knot]
        }
        let p = way.perched
        // The kit's peg has a darker underside; on Brass the metal is already black.
        let pegShadow = plumage == .brass ? p.metal : "#7E6436"
        return ["body": p.body, "feather": p.feather, "stitch": p.stitch, "wingSatin": p.wingSatin, "egg": p.egg, "eggText": p.eggText,
                "beak": p.beak, "crest": p.crest, "eye": p.eye, "metal": p.metal, "halo": p.halo, "pegShadow": pegShadow]
    }

    // MARK: The count on the egg

    static func registerFont() {
        guard let url = Bundle.main.url(forResource: "BodoniModa-Italic", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    private static func countFont(size: CGFloat) -> CTFont {
        let wght = 0x77676874, opsz = 0x6F70737A // the 'wght' and 'opsz' axes; the smallest optical size keeps hairlines visible at 10 pt
        let attributes: [CFString: Any] = [kCTFontFamilyNameAttribute: "Bodoni Moda", kCTFontVariationAttribute: [wght: 500, opsz: 6]]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        let base = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        return CTFontCreateCopyWithSymbolicTraits(base, size, nil, .traitItalic, .traitItalic) ?? base
    }

    /// The number as a bitmap on a 40-unit square, with the egg's centre in the middle.
    static func countImage(_ text: String, colour: String) -> CGImage? {
        let scale = pixelsPerUnit * 2, side = Int(40 * scale)
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        let size: CGFloat = text.count > 1 ? 9.5 : 11
        let attributed = NSAttributedString(string: text, attributes: [.font: countFont(size: size), .foregroundColor: NSColor(hex: colour)])
        let line = CTLineCreateWithAttributedString(attributed)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        context.textPosition = CGPoint(x: 20 - width / 2, y: 20 - 3.7)
        CTLineDraw(line, context)
        return context.makeImage()
    }
}
