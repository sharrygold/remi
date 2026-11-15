import AppKit
import SwiftUI

/// A visible handle in the panel's bottom corner, on the side away from the companion, so resizing
/// doesn't depend on finding the thin edge of a borderless window.
struct ResizeGrip: View {
    /// True for the bottom-left corner, used when the companion sits to the panel's right.
    let leading: Bool
    let onEnd: () -> Void
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: leading ? .bottomLeading : .bottomTrailing) {
            // An arc on the panel's own rounded edge, clear of the capture bar, so it reads as part of the frame.
            Path { path in
                let middle = leading ? 135.0 : 45.0
                path.addArc(center: CGPoint(x: 24, y: 24), radius: 21,
                            startAngle: .degrees(middle - 28), endAngle: .degrees(middle + 28), clockwise: false)
            }
            .stroke(hovering ? AnyShapeStyle(Color.brand) : AnyShapeStyle(.secondary), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .opacity(hovering ? 1 : 0.75)
            .frame(width: 48, height: 48)
            .allowsHitTesting(false)
            GripHandle(leading: leading, onEnd: onEnd)
                .frame(width: 28, height: 28)
                .onHover { hovering = $0 }
                .help("Drag to resize")
        }
        .frame(width: 48, height: 48)
        .animation(Motion.hover, value: hovering)
        .accessibilityHidden(true)
    }
}

private struct GripHandle: NSViewRepresentable {
    let leading: Bool
    let onEnd: () -> Void

    func makeNSView(context: Context) -> GripView {
        let view = GripView()
        view.leading = leading
        view.onEnd = onEnd
        return view
    }

    func updateNSView(_ view: GripView, context: Context) {
        view.leading = leading
        view.onEnd = onEnd
        view.window?.invalidateCursorRects(for: view)
    }
}

final class GripView: NSView {
    var leading = false
    var onEnd: () -> Void = {}
    private var resize: PanelResize?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .frameResize(position: leading ? .bottomLeft : .bottomRight, directions: .all))
    }

    override func mouseDown(with event: NSEvent) {
        resize = window.map { PanelResize(window: $0, edges: leading ? [.bottom, .left] : [.bottom, .right]) }
    }

    override func mouseDragged(with event: NSEvent) { resize?.follow(NSEvent.mouseLocation) }

    override func mouseUp(with event: NSEvent) {
        resize?.end()
        resize = nil
        onEnd()
    }
}
