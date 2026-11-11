import AppKit
import SwiftUI

/// The two ways the companion can appear. Raw values are stored in settings and placement keys.
enum CompanionStyle: String, CaseIterable, Identifiable {
    case bird, cord

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bird: "Perched"
        case .cord: "On the cord"
        }
    }

    var windowSize: CGSize {
        switch self {
        case .bird: PerchedBirdView.windowSize
        case .cord: CordCompanionView.windowSize
        }
    }
}

/// How large the companion is drawn. Both companions read this when they are built.
enum CompanionSize: String, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var perchedScale: CGFloat {
        switch self {
        case .small: 1.15
        case .medium: 1.4
        case .large: 1.7
        }
    }

    var cordScale: CGFloat {
        switch self {
        case .small: 275.0 / 230
        case .medium: 320.0 / 230
        case .large: 375.0 / 230
        }
    }

    /// The sizes moved up one step on 2026-11-11, so whoever chose one keeps the size they were looking at.
    static func keepChosenSizeAfterRescale() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "companionSizeRescaled") else { return }
        defaults.set(true, forKey: "companionSizeRescaled")
        if let saved = defaults.string(forKey: CompanionKeys.size) {
            defaults.set(saved == "large" ? "medium" : "small", forKey: CompanionKeys.size)
        }
    }

    static var current: CompanionSize {
        if let text = CommandLine.arguments.first(where: { $0.hasPrefix("--size=") })?.dropFirst("--size=".count),
           let size = CompanionSize(rawValue: String(text)) { return size }
        return UserDefaults.standard.string(forKey: CompanionKeys.size).flatMap(CompanionSize.init) ?? .medium
    }
}

/// The companion's look, chosen in Settings and remembered.
final class CompanionSettings: ObservableObject {
    @Published var style: CompanionStyle {
        didSet { UserDefaults.standard.set(style.rawValue, forKey: CompanionKeys.style) }
    }
    @Published var plumage: Plumage {
        didSet { UserDefaults.standard.set(plumage.rawValue, forKey: CompanionKeys.plumage) }
    }

    @Published var size = CompanionSize.current {
        didSet { UserDefaults.standard.set(size.rawValue, forKey: CompanionKeys.size) }
    }

    init(style: CompanionStyle?, plumage: Plumage?) {
        let defaults = UserDefaults.standard
        // Anything unrecognised, such as the retired pebble, falls back to Perched.
        self.style = style ?? defaults.string(forKey: CompanionKeys.style).flatMap(CompanionStyle.init) ?? .bird
        self.plumage = plumage ?? defaults.string(forKey: CompanionKeys.plumage).flatMap(Plumage.init) ?? .ivory
    }
}

/// Runs the companion's springs while something is moving, and stops completely when nothing is.
/// A plain timer, because the view's display link never fired for the perched bird's window.
final class FrameClock {
    private var timer: Timer?
    private let tick: () -> Void

    init(tick: @escaping () -> Void) { self.tick = tick }

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

enum CompanionEvent {
    case taskAdded, linkCaught, taskDone, allDone
}

/// What the app asks of either companion.
protocol CompanionSurface: NSView {
    func configure(plumage: Plumage, onLeftEdge: Bool)
    func update(count: Int, allKept: Bool, event: CompanionEvent?)
    func setPanelOpen(_ open: Bool)
    func pointerMoved(toScreen point: NSPoint)
    func playMorningStretch()
    /// True when a point in the window, y down, should catch the mouse.
    func isHit(_ point: CGPoint) -> Bool
    func reduceMotionChanged()
}

/// Owns every mouse event on the companion, so clicks and drags don't depend on the drawing.
final class CompanionHostView: NSView {
    var onClick: (() -> Void)?
    /// When this returns true, dragging down pulls and dragging sideways slides along the edge.
    var isPullMode: () -> Bool = { false }
    var onDragStart: (() -> Void)?
    var onPullStart: (() -> Void)?
    var onPull: ((CGFloat) -> Void)?
    var onPullEnd: (() -> Void)?
    /// Receives the window's new left edge when a cord drag goes sideways.
    var onSlide: ((CGFloat) -> Void)?
    var onDragEnd: (() -> Void)?
    var onRightClick: ((NSEvent, NSView) -> Void)?
    private var sliding = false
    private var grabOffset = NSPoint.zero
    private var downMouse = NSPoint.zero
    private var dragged = false
    private let dragThreshold: CGFloat = 4

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event, self)
    }

    override func mouseDown(with event: NSEvent) {
        let origin = window?.frame.origin ?? .zero
        downMouse = NSEvent.mouseLocation
        grabOffset = NSPoint(x: downMouse.x - origin.x, y: downMouse.y - origin.y)
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        let mouse = NSEvent.mouseLocation
        if !dragged && hypot(mouse.x - downMouse.x, mouse.y - downMouse.y) < dragThreshold { return }
        if !dragged {
            sliding = abs(mouse.x - downMouse.x) > abs(mouse.y - downMouse.y)
            if isPullMode() {
                if !sliding { onPullStart?() }
            } else {
                onDragStart?()
            }
        }
        dragged = true
        if isPullMode() {
            if sliding {
                onSlide?(mouse.x - grabOffset.x)
            } else {
                onPull?(downMouse.y - mouse.y)
            }
            return
        }
        window?.setFrameOrigin(NSPoint(x: mouse.x - grabOffset.x, y: mouse.y - grabOffset.y))
    }

    override func mouseUp(with event: NSEvent) {
        if isPullMode() && dragged {
            if sliding { onDragEnd?() } else { onPullEnd?() }
            return
        }
        if dragged {
            onDragEnd?()
            return
        }
        if event.clickCount == 1 { onClick?() }
    }
}

extension CALayer {
    /// A layer the size of the art canvas, turning about a point given in art coordinates (y down).
    static func pivot(at point: CGPoint, canvas: CGSize, in parent: CGSize? = nil) -> CALayer {
        let layer = CALayer()
        layer.bounds = CGRect(origin: .zero, size: canvas)
        layer.anchorPoint = CGPoint(x: point.x / canvas.width, y: 1 - point.y / canvas.height)
        let outer = parent ?? canvas
        layer.position = CGPoint(x: point.x, y: outer.height - point.y)
        return layer
    }
}

extension CALayer {
    /// A canvas-sized layer whose centre sits at a point in the parent's art (y down), for art drawn around its own origin.
    static func centred(at point: CGPoint, canvas: CGSize) -> CALayer {
        let layer = CALayer()
        layer.bounds = CGRect(origin: .zero, size: canvas)
        layer.position = CGPoint(x: point.x, y: canvas.height - point.y)
        return layer
    }
}

/// Runs a block in one frame with no implicit animations.
func withoutAnimation(_ work: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    work()
    CATransaction.commit()
}

func radians(_ degrees: Double) -> CGFloat { CGFloat(degrees * .pi / 180) }
