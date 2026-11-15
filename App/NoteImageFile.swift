import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Turns pasted or dropped pictures into small files for notes: at most 1600 pixels on the long side,
/// JPEG unless the picture has see-through parts, and remembering its size on screen so a small
/// picture stays small.
enum NoteImageFile {
    static let maxPixels = 1600
    static let jpegQuality = 0.82

    /// Pictures on a pasteboard, or nil when it holds text (or anything else) to paste normally.
    /// Image files copied in Finder count; so does image data, unless text comes first.
    static func images(on pasteboard: NSPasteboard) -> [(data: Data, points: CGSize?)]? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true,
                                                            .urlReadingContentsConformToTypes: [UTType.image.identifier]]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty {
            let files = urls.compactMap { url in (try? Data(contentsOf: url)).map { (data: $0, points: NSImage(contentsOf: url)?.size) } }
            return files.isEmpty ? nil : files
        }
        let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, NSPasteboard.PasteboardType(UTType.jpeg.identifier),
                                                         NSPasteboard.PasteboardType(UTType.heic.identifier)]
        guard let types = pasteboard.types, let first = types.first(where: { imageTypes.contains($0) || $0 == .string }),
              first != .string, let data = pasteboard.data(forType: first) else { return nil }
        return [(data, NSImage(data: data)?.size)]
    }

    /// Writes one picture into `folder` and returns its file name.
    static func save(_ data: Data, points: CGSize?, in folder: URL) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int, pixelWidth > 0 else { return nil }
        let thumbnail: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                          kCGImageSourceCreateThumbnailWithTransform: true,
                                          kCGImageSourceThumbnailMaxPixelSize: maxPixels]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnail as CFDictionary) else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        // Pixels per point in the original (2 for a Retina screenshot); kept so it shows at its own size.
        let sourceWidthInPoints = orientation >= 5 ? points?.height : points?.width
        let density = max(1, CGFloat(pixelWidth) / max(sourceWidthInPoints ?? CGFloat(pixelWidth), 1))
        let hasAlpha = ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let type = hasAlpha ? UTType.png : UTType.jpeg
        let name = UUID().uuidString + (hasAlpha ? ".png" : ".jpg")
        let url = folder.appendingPathComponent(name)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { return nil }
        var output: [CFString: Any] = [kCGImagePropertyDPIWidth: 72 * density, kCGImagePropertyDPIHeight: 72 * density]
        if !hasAlpha { output[kCGImageDestinationLossyCompressionQuality] = jpegQuality }
        CGImageDestinationAddImage(destination, image, output as CFDictionary)
        return CGImageDestinationFinalize(destination) ? name : nil
    }
}

/// A picture in a note. It is drawn as wide as the note allows (never wider than its own size) and
/// no taller than `maxHeight`, and it reflows when the panel is resized.
final class ImageAttachment: NSTextAttachment {
    let name: String

    init(name: String, url: URL) {
        self.name = name
        super.init(data: nil, ofType: nil)
        attachmentCell = NoteImageCell(image: NSImage(contentsOf: url))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    var picture: NSImage? { (attachmentCell as? NoteImageCell)?.picture }

    static func string(name: String, url: URL) -> NSAttributedString {
        NSAttributedString(attachment: ImageAttachment(name: name, url: url))
    }
}

final class NoteImageCell: NSTextAttachmentCell {
    static let maxHeight: CGFloat = 420
    let picture: NSImage?

    init(image: NSImage?) {
        picture = image
        super.init(imageCell: nil)
    }

    required init(coder: NSCoder) { fatalError("not used") }

    override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect,
                            glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        let natural = picture?.size ?? NSSize(width: 220, height: 64)
        let room = max(textContainer.size.width - textContainer.lineFragmentPadding * 2 - 2, 40)
        let scale = min(1, room / max(natural.width, 1), Self.maxHeight / max(natural.height, 1))
        return NSRect(x: 0, y: 0, width: floor(natural.width * scale), height: floor(natural.height * scale))
    }

    override func cellBaselineOffset() -> NSPoint { .zero }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int, layoutManager: NSLayoutManager) {
        let shape = NSBezierPath(roundedRect: cellFrame, xRadius: 8, yRadius: 8)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        if let picture {
            picture.draw(in: cellFrame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        } else {
            NSColor.quaternaryLabelColor.setFill()
            shape.fill()
            let label = NSAttributedString(string: "Image missing", attributes: [.font: NSFont.preferredFont(forTextStyle: .footnote),
                                                                                .foregroundColor: NSColor.secondaryLabelColor])
            let size = label.size()
            label.draw(at: NSPoint(x: cellFrame.midX - size.width / 2, y: cellFrame.midY - size.height / 2))
        }
        // Selected pictures get a tint, since the text view's own highlight is hidden behind them.
        if let textView = controlView as? NSTextView,
           textView.selectedRanges.contains(where: { NSLocationInRange(charIndex, $0.rangeValue) }) {
            NSColor.brand.withAlphaComponent(0.3).setFill()
            shape.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        NSColor.separatorColor.setStroke()
        NSBezierPath(roundedRect: cellFrame.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        guard let layoutManager = (controlView as? NSTextView)?.layoutManager else { return }
        draw(withFrame: cellFrame, in: controlView, characterIndex: NSNotFound, layoutManager: layoutManager)
    }
}
