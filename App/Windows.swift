import AppKit
import SwiftUI

final class HandleWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PanelWindow: NSPanel {
    var onCancel: (() -> Void)?
    /// True while the capture or search field has focus; those keep it when you click elsewhere.
    var keepsFieldFocus: () -> Bool = { false }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }

    /// A click outside a row's rename field ends the rename, which AppKit doesn't do on its own
    /// when the click lands on something that can't take focus.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, !keepsFieldFocus(),
           let editor = firstResponder as? NSTextView, editor.isFieldEditor,
           let field = editor.delegate as? NSView,
           !field.convert(field.bounds, to: nil).contains(event.locationInWindow) {
            makeFirstResponder(nil)
        }
        super.sendEvent(event)
    }
}

/// Settings takes keyboard focus without activating the app, which macOS often refuses for a
/// background app; the floating panel works the same way.
final class SettingsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns every mouse event on the handle, so clicks and drags never depend on SwiftUI gestures
/// or on how see-through the glass is at the pointer.
final class HandleHostingView<Content: View>: NSHostingView<Content> {
    var onClick: (() -> Void)?
    /// When this returns true, dragging pulls instead of moving the window.
    var isPullMode: () -> Bool = { false }
    var onPull: ((CGFloat, CGFloat) -> Void)?
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
        if !dragged { sliding = abs(mouse.x - downMouse.x) > abs(mouse.y - downMouse.y) }
        dragged = true
        if isPullMode() {
            if sliding {
                onSlide?(mouse.x - grabOffset.x)
            } else {
                onPull?(mouse.x - downMouse.x, downMouse.y - mouse.y)
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
        if !dragged && event.clickCount == 1 { onClick?() }
    }
}
