import SwiftUI

/// Quiet buttons show a soft grey highlight under the pointer, as Apple's toolbars do, so it's
/// clear what a click will hit and how big the target is. Pressing darkens it a little more.
struct HoverHighlight: ViewModifier {
    var radius: CGFloat = 6
    var pressed = false
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.primary.opacity(pressed ? 0.15 : (hovering && isEnabled ? 0.08 : 0)))
            }
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onHover { hovering = $0 }
            .animation(Motion.hover, value: hovering)
    }
}

extension View {
    /// The grey hover highlight, for controls that can't take `HoverButtonStyle` (menus, AppKit buttons).
    func hoverHighlight(radius: CGFloat = 6) -> some View { modifier(HoverHighlight(radius: radius)) }

    /// A square icon target: the symbol centred in a box big enough to hit without aiming.
    func iconTarget(_ size: CGFloat = Tokens.Size.iconTarget) -> some View {
        frame(width: size, height: size).contentShape(Rectangle())
    }
}

/// A plain button with the hover highlight and the small press give of `PressScale`.
/// The label sets its own size (`iconTarget()` for symbols, padding for words).
struct HoverButtonStyle: ButtonStyle {
    var radius: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(HoverHighlight(radius: radius, pressed: configuration.isPressed))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(configuration.isPressed ? Motion.press : Motion.release, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == HoverButtonStyle {
    static var hover: HoverButtonStyle { HoverButtonStyle() }
}
