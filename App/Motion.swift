import SwiftUI

/// The motion system, ported from MOTION.md. Its numbers are the source of truth: three curves,
/// a few speeds, short distances. Calm and physical: things arrive quickly and settle slowly, and
/// nothing bounces except the completion pop. Every animation in the panel and Settings uses these.
enum Motion {
    // The three curves, exact.
    static func ease(_ duration: Double = 0.22) -> Animation { .timingCurve(0.2, 0.7, 0.2, 1, duration: duration) }
    static func easeOut(_ duration: Double = 0.5) -> Animation { .timingCurve(0.16, 1, 0.3, 1, duration: duration) }
    static func easeInOut(_ duration: Double = 0.45) -> Animation { .timingCurve(0.65, 0, 0.35, 1, duration: duration) }

    /// The sliding highlight.
    static let glide = easeOut(0.5)
    /// A pane inside the panel or Settings easing in.
    static let pane = easeOut(0.44)
    /// Accordions and chevrons.
    static let open = easeInOut(0.45)
    /// Rows leaving, with the rows below sliding up.
    static let collapse = easeInOut(0.45)
    /// Cards, inline fields and the panel itself arriving.
    static let modal = easeOut(0.42)
    static let toast = easeOut(0.45)
    static let hover = ease(0.22)
    static let press = Animation.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.08)
    static let release = ease(0.18)
    /// The only overshoot in the system: a check mark landing.
    static let pop = Animation.spring(response: 0.35, dampingFraction: 0.55)
    /// Reduce Motion: a short plain fade.
    static let reduced = Animation.linear(duration: 0.16)

    static func adaptive(_ animation: Animation, reduce: Bool) -> Animation { reduce ? reduced : animation }

    // MARK: Transitions

    /// Toasts and confirmations: rise 14 pt with a hint of scale; leave by fading and dropping 8 pt.
    static func toast(reduce: Bool) -> AnyTransition {
        guard !reduce else { return .opacity.animation(reduced) }
        return .asymmetric(insertion: .opacity.combined(with: .offset(y: 14)).combined(with: .scale(scale: 0.98)).animation(toast),
                           removal: .opacity.combined(with: .offset(y: 8)).animation(ease(0.25)))
    }

    /// Cards and inline fields: 12 pt and scale 0.98 into place; out with a quick fade.
    static func modalIn(reduce: Bool) -> AnyTransition {
        guard !reduce else { return .opacity.animation(reduced) }
        return .asymmetric(insertion: .opacity.combined(with: .offset(y: 12)).combined(with: .scale(scale: 0.98)).animation(modal),
                           removal: .opacity.animation(ease(0.25)))
    }

    /// Rows: soft-rise in; fade out while the rows below close the gap.
    static func row(reduce: Bool) -> AnyTransition {
        guard !reduce else { return .opacity }
        return .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity)
    }

    /// One whole pane replacing another: no exit, the new one eases in and rises 8 pt.
    static func paneSwap(reduce: Bool) -> AnyTransition {
        .asymmetric(insertion: reduce ? .opacity : .opacity.combined(with: .offset(y: 8)), removal: .identity)
    }

    /// Accordion content: fades in and drops 4 pt a moment after the height starts opening.
    static func accordion(reduce: Bool) -> AnyTransition {
        guard !reduce else { return .opacity }
        return .asymmetric(insertion: .opacity.combined(with: .offset(y: -4)).animation(easeOut(0.5).delay(0.1)),
                           removal: .opacity.animation(ease(0.25)))
    }
}

// MARK: Press feedback

/// Gives a little under the pointer straight away: 0.96 for small controls, 0.98 for wide ones.
struct PressScale: ButtonStyle {
    var scale: CGFloat = 0.96
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .animation(configuration.isPressed ? Motion.press : Motion.release, value: configuration.isPressed)
    }
}

// MARK: Pane enter

/// When `key` changes, the content is swapped at once and the new one fades in and rises into
/// place. Never on first appearance, and no exit animation, which keeps switching quick.
struct PaneEnter: ViewModifier {
    let key: AnyHashable
    var y: CGFloat = 8
    var duration: Double = 0.44
    @State private var shown = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : y)
            .onChange(of: key) { _, _ in
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) { shown = false }
                withAnimation(reduceMotion ? Motion.reduced : Motion.easeOut(duration)) { shown = true }
            }
    }
}

extension View {
    func paneEnter(_ key: AnyHashable, y: CGFloat = 8, duration: Double = 0.44) -> some View {
        modifier(PaneEnter(key: key, y: y, duration: duration))
    }
}

// MARK: Sliding highlight

/// Each item in a group reports where it is; the group draws one highlight behind the selected one.
private struct GliderAnchors: PreferenceKey {
    static let defaultValue: [AnyHashable: Anchor<CGRect>] = [:]
    static func reduce(value: inout [AnyHashable: Anchor<CGRect>], nextValue: () -> [AnyHashable: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Marks an item the group's highlight can sit behind.
    func gliderItem(_ id: AnyHashable) -> some View {
        anchorPreference(key: GliderAnchors.self, value: .bounds) { [id: $0] }
    }

    /// One highlight shape for the whole group, which travels from the old item to the new one,
    /// matching its frame. It is placed without animation the first time and when the group is
    /// resized; only a change of selection moves it.
    func glider<Highlight: View>(selection: AnyHashable, reduce: Bool, @ViewBuilder highlight: @escaping () -> Highlight) -> some View {
        backgroundPreferenceValue(GliderAnchors.self) { anchors in
            GeometryReader { proxy in
                if let anchor = anchors[selection] {
                    let frame = proxy[anchor]
                    highlight()
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                        .animation(reduce ? Motion.reduced : Motion.glide, value: selection)
                }
            }
        }
    }
}

// MARK: Disclosure chevron

/// Points right when closed and down when open, turning on the accordion curve.
struct DisclosureChevron: View {
    let open: Bool

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .rotationEffect(.degrees(open ? 90 : 0))
            .opacity(open ? 0.8 : 0.55)
            .animation(Motion.open, value: open)
            .accessibilityHidden(true)
    }
}
