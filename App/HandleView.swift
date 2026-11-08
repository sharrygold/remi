import SwiftUI

enum HandleStyle: String {
    case edgeTab, tile
}

/// The always-visible object on the screen edge.
struct HandleView: View {
    let style: HandleStyle
    let count: Int
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: AnyShape {
        switch style {
        case .edgeTab:
            AnyShape(UnevenRoundedRectangle(
                topLeadingRadius: Tokens.Radius.medium,
                bottomLeadingRadius: Tokens.Radius.medium,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous))
        case .tile:
            AnyShape(RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous))
        }
    }

    private var size: CGSize { style == .edgeTab ? Tokens.Size.edgeTab : Tokens.Size.tile }

    var body: some View {
        Group {
            if style == .edgeTab {
                Text("\(count)").font(Tokens.TextRole.detail.weight(.semibold))
            } else {
                Image(systemName: "checklist").font(.title3)
                    .overlay(alignment: .topTrailing) {
                        Text("\(count)").font(.caption2.weight(.semibold)).offset(x: 10, y: -10)
                    }
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(shape)
        .background {
            if reduceTransparency { shape.fill(Color(nsColor: .windowBackgroundColor)) }
        }
        .glassEffect(reduceTransparency ? .identity : .regular.interactive(), in: shape)
        .scaleEffect(hovering && !reduceMotion ? 1.06 : 1, anchor: style == .edgeTab ? .trailing : .center)
        .animation(reduceMotion ? nil : Tokens.Motion.quick, value: hovering)
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .accessibilityElement()
        .accessibilityLabel("\(AppInfo.displayName), \(count) tasks today")
        .accessibilityAddTraits(.isButton)
    }
}
