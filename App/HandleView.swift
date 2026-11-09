import SwiftUI

/// Every look the floating object can take. The user can switch between these; adding one is one case here.
enum HandleStyle: String, CaseIterable, Identifiable {
    case edgeTab, tile, pill, accentPill, nextUp, countTile, accentTile, haloTile, dots, stack, bookmark, sticky, pebble, bird

    var id: String { rawValue }

    var title: String {
        switch self {
        case .edgeTab: "Edge tab"
        case .tile: "Icon tile"
        case .pill: "Floating pill"
        case .accentPill: "Colour pill"
        case .nextUp: "Next-up pill"
        case .countTile: "Big count"
        case .accentTile: "Colour tile"
        case .haloTile: "Halo tile"
        case .dots: "Task dots"
        case .stack: "Card stack"
        case .bookmark: "Bookmark"
        case .sticky: "Sticky note"
        case .pebble: "Pebble pet"
        case .bird: "Perched bird"
        }
    }

    var size: CGSize {
        switch self {
        case .edgeTab: Tokens.Size.edgeTab
        case .tile: Tokens.Size.tile
        case .pill, .accentPill, .dots: CGSize(width: 36, height: 88)
        case .nextUp: CGSize(width: 188, height: 40)
        case .countTile, .accentTile, .haloTile, .sticky, .bird: CGSize(width: 56, height: 56)
        case .stack: CGSize(width: 64, height: 64)
        case .bookmark: CGSize(width: 44, height: 72)
        case .pebble: CGSize(width: 68, height: 56)
        }
    }

    var attachesToEdge: Bool { self == .edgeTab }

    var shape: AnyShape {
        let radius = Tokens.Radius.medium
        switch self {
        case .edgeTab:
            return AnyShape(UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: radius,
                                                   bottomTrailingRadius: 0, topTrailingRadius: 0, style: .continuous))
        case .pill, .accentPill, .dots, .nextUp:
            return AnyShape(Capsule(style: .continuous))
        case .bookmark:
            return AnyShape(BookmarkShape())
        case .pebble:
            return AnyShape(PebbleShape())
        case .countTile, .accentTile, .haloTile, .bird, .sticky:
            return AnyShape(RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous))
        case .tile, .stack:
            return AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }

    var glass: Glass {
        .regular.interactive()
    }

    /// Solid colour under the glass; `Glass.tint` rendered gray on these non-key windows.
    var fill: Color? {
        switch self {
        case .accentPill, .accentTile: .accentColor
        case .sticky: Color(red: 0.96, green: 0.80, blue: 0.36)
        default: nil
        }
    }
}

struct BookmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = Tokens.Radius.medium
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - 14))
        path.closeSubpath()
        return path
    }
}

struct PebbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: 0.08 * w, y: 0.55 * h))
        path.addCurve(to: CGPoint(x: 0.52 * w, y: 0), control1: CGPoint(x: 0.04 * w, y: 0.2 * h), control2: CGPoint(x: 0.25 * w, y: 0))
        path.addCurve(to: CGPoint(x: w, y: 0.5 * h), control1: CGPoint(x: 0.82 * w, y: 0), control2: CGPoint(x: w, y: 0.18 * h))
        path.addCurve(to: CGPoint(x: 0.5 * w, y: h), control1: CGPoint(x: w, y: 0.84 * h), control2: CGPoint(x: 0.8 * w, y: h))
        path.addCurve(to: CGPoint(x: 0.08 * w, y: 0.55 * h), control1: CGPoint(x: 0.22 * w, y: h), control2: CGPoint(x: 0.1 * w, y: 0.86 * h))
        path.closeSubpath()
        return path
    }
}

/// The always-visible object on the screen.
struct HandleView: View {
    let style: HandleStyle
    let count: Int
    var nextTitle = ""
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder private var content: some View {
        switch style {
        case .edgeTab, .pill, .accentPill, .bookmark:
            Text("\(count)").font(.headline)
        case .tile:
            Image(systemName: "checklist").font(.title3)
                .overlay(alignment: .topTrailing) {
                    Text("\(count)").font(.caption2.weight(.semibold)).offset(x: 10, y: -10)
                }
        case .nextUp:
            HStack(spacing: Tokens.Spacing.s) {
                Text("\(count)").font(.headline)
                Text(nextTitle).font(Tokens.TextRole.detail).lineLimit(1)
            }
            .padding(.horizontal, Tokens.Spacing.m)
        case .countTile, .accentTile, .stack:
            Text("\(count)").font(.title.weight(.semibold))
        case .haloTile:
            Text("\(count)").font(.title.weight(.semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay { style.shape.stroke(Color.accentColor, lineWidth: 2.5) }
        case .sticky:
            Text("\(count)").font(.title2.weight(.semibold)).foregroundStyle(.black.opacity(0.75))
        case .dots:
            VStack(spacing: Tokens.Spacing.xs + 2) {
                ForEach(0..<min(count, 7), id: \.self) { _ in Circle().frame(width: 7, height: 7) }
            }
        case .pebble:
            HStack(spacing: Tokens.Spacing.m) {
                Capsule().frame(width: 6, height: 12)
                Capsule().frame(width: 6, height: 12)
            }
        case .bird:
            Image(systemName: "bird.fill").font(.title2)
        }
    }

    var body: some View {
        content
            .frame(width: style == .stack ? 52 : style.size.width, height: style == .stack ? 52 : style.size.height)
            .foregroundStyle(style.fill != nil && style != .sticky ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background {
                if let fill = style.fill { style.shape.fill(fill) }
            }
            .contentShape(style.shape)
            .background {
                if reduceTransparency { style.shape.fill(Color(nsColor: .windowBackgroundColor)) }
            }
            .glassEffect(reduceTransparency ? .identity : style.glass, in: style.shape)
            .background {
                if style == .stack {
                    style.shape.fill(.clear)
                        .frame(width: 52, height: 52)
                        .glassEffect(.regular, in: style.shape)
                        .offset(x: -6, y: -6)
                }
            }
            .rotationEffect(style == .sticky ? .degrees(-5) : .zero)
            .offset(x: style == .stack ? 3 : 0, y: style == .stack ? 3 : 0)
            .scaleEffect(hovering && !reduceMotion ? 1.06 : 1, anchor: style.attachesToEdge ? .trailing : .center)
            .animation(reduceMotion ? nil : Tokens.Motion.quick, value: hovering)
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
            .frame(width: style.size.width, height: style.size.height)
            .accessibilityElement()
            .accessibilityLabel("\(AppInfo.displayName), \(count) tasks today")
            .accessibilityAddTraits(.isButton)
    }
}

/// Phase 1 only: every handle side by side over the real desktop.
struct HandleGalleryView: View {
    private let columns = Array(repeating: GridItem(.fixed(200), spacing: Tokens.Spacing.m), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: Tokens.Spacing.l) {
            ForEach(Array(HandleStyle.allCases.enumerated()), id: \.element) { index, style in
                VStack(spacing: Tokens.Spacing.s) {
                    HandleView(style: style, count: 5, nextTitle: Sample.today[0].title) {}
                        .frame(height: 96)
                    Text("\(index + 1). \(style.title)")
                        .font(Tokens.TextRole.detail.weight(.medium))
                        .padding(.horizontal, Tokens.Spacing.s)
                        .padding(.vertical, Tokens.Spacing.xs)
                        .background(.regularMaterial, in: Capsule())
                }
            }
        }
        .padding(Tokens.Spacing.l)
        .frame(width: 1140, height: 520)
    }
}
