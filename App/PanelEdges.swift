import AppKit
import SwiftUI

/// Which sides of the panel a drag moves.
struct PanelEdgeSet: OptionSet, Hashable {
    let rawValue: Int
    static let left = PanelEdgeSet(rawValue: 1)
    static let right = PanelEdgeSet(rawValue: 2)
    static let top = PanelEdgeSet(rawValue: 4)
    static let bottom = PanelEdgeSet(rawValue: 8)
}

/// One resize drag: the dragged sides follow the pointer, the opposite sides stay put, and the size
/// stays between the panel's smallest and largest.
struct PanelResize {
    let window: NSWindow
    let edges: PanelEdgeSet
    let startFrame: NSRect
    let startMouse: NSPoint

    init(window: NSWindow, edges: PanelEdgeSet) {
        self.window = window
        self.edges = edges
        startFrame = window.frame
        startMouse = NSEvent.mouseLocation
        (window as? PanelWindow)?.isResizingByHand = true
    }

    func follow(_ mouse: NSPoint) {
        let dx = mouse.x - startMouse.x, dy = mouse.y - startMouse.y
        let min = Tokens.Size.panelMin, max = Tokens.Size.panelMax
        func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat { Swift.min(Swift.max(value, low), high) }
        var frame = startFrame
        // The side facing the companion grows only up to it; the companion itself never moves.
        let bird = (window as? PanelWindow)?.companionFrame()
        let gap = Tokens.Size.handleGap
        if edges.contains(.right) {
            var widest = max.width
            if let bird, bird.minX >= startFrame.maxX - 1 { widest = Swift.min(widest, bird.minX - gap - startFrame.minX) }
            frame.size.width = clamp(startFrame.width + dx, min.width, Swift.max(widest, startFrame.width))
        }
        if edges.contains(.left) {
            var widest = max.width
            if let bird, bird.maxX <= startFrame.minX + 1 { widest = Swift.min(widest, startFrame.maxX - bird.maxX - gap) }
            frame.size.width = clamp(startFrame.width - dx, min.width, Swift.max(widest, startFrame.width))
            frame.origin.x = startFrame.maxX - frame.width
        }
        if edges.contains(.top) { frame.size.height = clamp(startFrame.height + dy, min.height, max.height) }
        if edges.contains(.bottom) {
            frame.size.height = clamp(startFrame.height - dy, min.height, max.height)
            frame.origin.y = startFrame.maxY - frame.height
        }
        window.setFrame(frame, display: true)
    }

    func end() {
        (window as? PanelWindow)?.isResizingByHand = false
    }
}

/// The panel's content plus invisible strips along every edge and corner that resize it. The glass
/// would otherwise take a press on the top edge as a move, and a borderless window's own edge is a
/// single hard-to-find pixel.
final class PanelContainerView: NSView {
    /// How far in from the window's edge a press resizes rather than moves.
    static let edgeReach: CGFloat = 7
    static let cornerReach: CGFloat = 14

    var onResizeEnd: () -> Void = {} {
        didSet { zones.forEach { $0.onEnd = onResizeEnd } }
    }
    private var zones: [EdgeZone] = []

    init(content: NSView) {
        super.init(frame: content.frame)
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        addSubview(content)
        let all: [PanelEdgeSet] = [.left, .right, .top, .bottom, [.top, .left], [.top, .right], [.bottom, .left], [.bottom, .right]]
        for edges in all {
            let zone = EdgeZone(edges: edges)
            addSubview(zone)
            zones.append(zone)
        }
        layoutZones()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        layoutZones()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutZones()
    }

    private func layoutZones() {
        let e = Self.edgeReach, c = Self.cornerReach
        let w = bounds.width, h = bounds.height
        for zone in zones {
            let edges = zone.edges
            let x: CGFloat = edges.contains(.left) ? 0 : edges.contains(.right) ? w - (edges.contains(.top) || edges.contains(.bottom) ? c : e) : c
            let y: CGFloat = edges.contains(.bottom) ? 0 : edges.contains(.top) ? h - (edges.contains(.left) || edges.contains(.right) ? c : e) : c
            let isCorner = edges.rawValue.nonzeroBitCount == 2
            let width: CGFloat = isCorner ? c : (edges == .top || edges == .bottom) ? w - 2 * c : e
            let height: CGFloat = isCorner ? c : (edges == .left || edges == .right) ? h - 2 * c : e
            zone.frame = NSRect(x: x, y: y, width: max(width, 0), height: max(height, 0))
        }
        window?.invalidateCursorRects(for: self)
        zones.forEach { window?.invalidateCursorRects(for: $0) }
    }
}

private final class EdgeZone: NSView {
    let edges: PanelEdgeSet
    var onEnd: () -> Void = {}
    private var resize: PanelResize?

    init(edges: PanelEdgeSet) {
        self.edges = edges
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    private var position: NSCursor.FrameResizePosition {
        switch edges {
        case .left: .left
        case .right: .right
        case .top: .top
        case .bottom: .bottom
        case [.top, .left]: .topLeft
        case [.top, .right]: .topRight
        case [.bottom, .left]: .bottomLeft
        default: .bottomRight
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .frameResize(position: position, directions: .all))
    }

    override func mouseDown(with event: NSEvent) {
        resize = window.map { PanelResize(window: $0, edges: edges) }
    }

    override func mouseDragged(with event: NSEvent) { resize?.follow(NSEvent.mouseLocation) }

    override func mouseUp(with event: NSEvent) {
        guard let resize else { return }
        resize.end()
        self.resize = nil
        onEnd()
    }
}

/// A small bar at the top centre of the panel that moves it, so moving has an obvious home of its
/// own and the top edge itself is free for resizing. The companion comes along.
struct MoveGrabber: View {
    @State private var hovering = false

    var body: some View {
        Capsule()
            .fill(.secondary)
            .frame(width: 36, height: 5)
            .opacity(hovering ? 0.9 : 0.45)
            .frame(width: 64, height: 16)
            .contentShape(Rectangle())
            .overlay { GrabberDrag() }
            .onHover { hovering = $0 }
            .animation(Motion.hover, value: hovering)
            .help("Drag to move")
            .accessibilityHidden(true)
    }
}

private struct GrabberDrag: NSViewRepresentable {
    func makeNSView(context: Context) -> GrabberView { GrabberView() }
    func updateNSView(_ view: GrabberView, context: Context) {}
}

final class GrabberView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) {
        NSCursor.closedHand.push()
        window?.performDrag(with: event)
        NSCursor.pop()
    }
}
