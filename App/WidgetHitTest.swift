import AppKit

/// Finds whether the widget has drawn anything under a point, from a snapshot of its window.
/// The snapshot is refreshed at most every 0.25 s and only while the pointer is inside the window.
enum WidgetHitTest {
    /// How close to the drawing still counts, so the edge of the bird is easy to grab.
    static let reach = 4
    private static var snapshot: NSBitmapImageRep?
    private static var taken = Date.distantPast
    private static weak var source: NSView?

    static func isDrawn(at point: NSPoint, in view: NSView) -> Bool {
        if source !== view || Date().timeIntervalSince(taken) > 0.25 || snapshot == nil {
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return true }
            view.cacheDisplay(in: view.bounds, to: rep)
            snapshot = rep
            taken = Date()
            source = view
        }
        guard let rep = snapshot else { return true }
        let scaleX = CGFloat(rep.pixelsWide) / max(view.bounds.width, 1)
        let scaleY = CGFloat(rep.pixelsHigh) / max(view.bounds.height, 1)
        // Bitmap rows start at the top; flip unless the view already does.
        let y = view.isFlipped ? point.y : view.bounds.height - point.y
        let centre = (x: Int(point.x * scaleX), y: Int(y * scaleY))
        let step = max(1, Int(scaleX))
        for dy in stride(from: -reach * step, through: reach * step, by: step * 2) {
            for dx in stride(from: -reach * step, through: reach * step, by: step * 2) {
                let x = centre.x + dx, y = centre.y + dy
                guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh else { continue }
                if (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.15 { return true }
            }
        }
        return false
    }
}
