import AppKit
import LinkPresentation

/// Fetches a page's title and icon. LinkPresentation first (no API keys), then two fallbacks that only
/// talk to the site itself: the video site's public oEmbed endpoint for a title, and `/favicon.ico`.
/// YouTube often answers LinkPresentation with a bot check, which is why the oEmbed step exists.
final class LinkMetadataFetcher {
    private let store: LibraryStore
    private var active = Set<UUID>()
    /// Links already tried this launch, so a site that is down is retried next launch, not on every open.
    private var attempted = Set<UUID>()

    init(store: LibraryStore) {
        self.store = store
    }

    func fetch(_ link: LinkItem) {
        guard let url = link.url, !active.contains(link.id) else { return }
        let id = link.id
        active.insert(id)
        attempted.insert(id)
        Task { @MainActor in
            let (title, icon) = await Self.lookUp(url)
            active.remove(id)
            // Nothing found usually means offline: leave it unfetched so it is tried again later.
            guard title != nil || icon != nil else { return }
            store.setMetadata(for: id, title: title, iconData: icon)
        }
    }

    /// Retries links saved while offline. Called when the panel opens.
    func fetchMissing() {
        for link in store.links where !link.titleFetched && !attempted.contains(link.id) {
            fetch(link)
        }
    }

    @MainActor
    static func lookUp(_ url: URL) async -> (title: String?, icon: Data?) {
        let provider = LPMetadataProvider()
        provider.timeout = 15
        let metadata = try? await provider.startFetchingMetadata(for: url)
        // Video sites answer oEmbed with the video's own title. LinkPresentation can return the channel
        // name instead (seen with youtu.be short links), so oEmbed goes first where it exists.
        var title = await oEmbedTitle(for: url)
        if title?.isEmpty ?? true { title = metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines) }
        var icon: Data?
        if let iconProvider = metadata?.iconProvider { icon = await image(from: iconProvider) }
        if icon == nil { icon = await favicon(for: url) }
        return (title?.isEmpty == false ? title : nil, icon)
    }

    private static func image(from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                continuation.resume(returning: (image as? NSImage).flatMap { png($0, side: 64) })
            }
        }
    }

    private static func oEmbedTitle(for url: URL) async -> String? {
        let host = LinkClassifier.displayHost(url).lowercased()
        let endpoint: String
        switch host {
        case "youtube.com", "youtu.be", "music.youtube.com": endpoint = "https://www.youtube.com/oembed"
        case "vimeo.com": endpoint = "https://vimeo.com/api/oembed.json"
        default: return nil
        }
        var components = URLComponents(string: endpoint)
        components?.queryItems = [URLQueryItem(name: "url", value: url.absoluteString), URLQueryItem(name: "format", value: "json")]
        guard let request = components?.url,
              let (data, response) = try? await URLSession.shared.data(from: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["title"] as? String
    }

    private static func favicon(for url: URL) async -> Data? {
        guard let host = url.host(), let address = URL(string: "https://\(host)/favicon.ico"),
              let (data, response) = try? await URLSession.shared.data(from: address),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = NSImage(data: data), image.isValid else { return nil }
        return png(image, side: 64)
    }

    /// Icons are stored small; the list shows them at 20 pt.
    private static func png(_ image: NSImage, side: CGFloat) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
