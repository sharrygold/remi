import SwiftUI

enum PanelTab: String, CaseIterable, Identifiable {
    case today = "Today", tasks = "Tasks", notes = "Notes", links = "Links"
    var id: String { rawValue }
}

struct PanelView: View {
    let density: Density
    @State var tab: PanelTab
    @State private var capture = ""
    @State private var selectedSpace: String? = nil
    @FocusState private var captureFocused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let shape = RoundedRectangle(cornerRadius: Tokens.Radius.panel, style: .continuous)

    var body: some View {
        VStack(spacing: Tokens.Spacing.s) {
            captureBar
            spaceSwitcher
            tabs
            content
            footer
        }
        .padding(Tokens.Spacing.s)
        .frame(width: Tokens.Size.panel.width, height: Tokens.Size.panel.height)
        .background {
            if reduceTransparency { shape.fill(Color(nsColor: .windowBackgroundColor)) }
        }
        .glassEffect(reduceTransparency ? .identity : .regular, in: shape)
        .onAppear { captureFocused = true }
    }

    private var captureBar: some View {
        HStack(spacing: Tokens.Spacing.s) {
            Image(systemName: "plus").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Capture a task, note or link", text: $capture)
                .textFieldStyle(.plain)
                .font(Tokens.TextRole.row)
                .focused($captureFocused)
                .accessibilityLabel("Capture")
        }
        .padding(.horizontal, Tokens.Spacing.m - Tokens.Spacing.xs)
        .frame(height: 40)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous))
    }

    private var spaceSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Tokens.Spacing.xs) {
                spaceChip(name: "All", symbol: "square.grid.2x2", tint: .accentColor, id: nil)
                ForEach(Sample.spaces) { spaceChip(name: $0.name, symbol: $0.symbol, tint: $0.tint, id: $0.name) }
            }
        }
    }

    private func spaceChip(name: String, symbol: String, tint: Color, id: String?) -> some View {
        let selected = selectedSpace == id
        return Button { selectedSpace = id } label: {
            Label(name, systemImage: symbol)
                .font(Tokens.TextRole.detail)
                .padding(.horizontal, Tokens.Spacing.s)
                .padding(.vertical, Tokens.Spacing.xs)
                .foregroundStyle(selected ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
                .background(selected ? tint.opacity(0.18) : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var tabs: some View {
        HStack(spacing: Tokens.Spacing.xs) {
            ForEach(PanelTab.allCases) { item in
                Button { tab = item } label: {
                    Text(item.rawValue)
                        .font(Tokens.TextRole.meta.weight(tab == item ? .semibold : .regular))
                        .foregroundStyle(tab == item ? .primary : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(tab == item ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                                    in: RoundedRectangle(cornerRadius: Tokens.Radius.small, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: density.sectionGap) {
                switch tab {
                case .today: todayContent
                case .tasks: tasksContent
                case .notes: notesContent
                case .links: linksContent
                }
            }
            .padding(Tokens.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(reduceTransparency ? 1 : 0.72),
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous))
    }

    private var todayContent: some View {
        Group {
            ForEach(Sample.spaces.filter { space in Sample.today.contains { $0.space == space } }) { space in
                section(space.name, tint: space.tint, symbol: space.symbol) {
                    ForEach(Sample.today.filter { $0.space == space }) { taskRow($0) }
                }
            }
            section("Still open", tint: .secondary, symbol: "clock") {
                ForEach(Sample.overdue) { taskRow($0) }
            }
            HStack {
                Label("Watch later", systemImage: "play.rectangle")
                Spacer()
                Text("\(Sample.watchLater.count)").foregroundStyle(.secondary)
            }
            .font(Tokens.TextRole.meta)
        }
    }

    private var tasksContent: some View {
        section("Upcoming", tint: .secondary, symbol: "tray") {
            ForEach(Sample.today + Sample.later) { taskRow($0) }
        }
    }

    private var notesContent: some View {
        ForEach(Sample.notes) { note in
            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                HStack(spacing: Tokens.Spacing.xs) {
                    if note.pinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.secondary) }
                    Text(note.title).font(Tokens.TextRole.sectionTitle)
                }
                Text(note.preview).font(Tokens.TextRole.detail).foregroundStyle(.secondary).lineLimit(2)
            }
            .padding(.vertical, density.rowPadding)
        }
    }

    private var linksContent: some View {
        Group {
            section("Saved links", tint: .secondary, symbol: "bookmark") { ForEach(Sample.saved) { linkRow($0) } }
            section("Watch later", tint: .secondary, symbol: "play.rectangle") { ForEach(Sample.watchLater) { linkRow($0) } }
        }
    }

    private func section<Rows: View>(_ title: String, tint: Color, symbol: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: density.rowPadding) {
            Label(title, systemImage: symbol).font(Tokens.TextRole.sectionTitle).foregroundStyle(tint)
            rows()
        }
    }

    private func taskRow(_ task: SampleTask) -> some View {
        HStack(spacing: Tokens.Spacing.s) {
            Image(systemName: "circle").foregroundStyle(.tertiary).accessibilityHidden(true)
            Text(task.title).font(Tokens.TextRole.row).lineLimit(1)
            if task.important { Image(systemName: "exclamationmark").font(.caption.bold()).foregroundStyle(.secondary) }
            Spacer(minLength: Tokens.Spacing.s)
            if let due = task.due { Text(due).font(Tokens.TextRole.detail).foregroundStyle(.secondary) }
            if task.hasAction { Image(systemName: "arrow.up.forward.square").foregroundStyle(.secondary) }
        }
        .padding(.vertical, density.rowPadding)
    }

    private func linkRow(_ link: SampleLink) -> some View {
        HStack(spacing: Tokens.Spacing.s) {
            Image(systemName: link.symbol).foregroundStyle(link.space.tint).frame(width: Tokens.Spacing.m + Tokens.Spacing.xs)
            VStack(alignment: .leading) {
                Text(link.title).font(Tokens.TextRole.row).lineLimit(1)
                Text(link.domain).font(Tokens.TextRole.detail).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, density.rowPadding)
    }

    private var footer: some View {
        HStack {
            Label("Search", systemImage: "magnifyingglass")
            Text("⌘F").foregroundStyle(.tertiary)
            Spacer()
            Image(systemName: "gearshape").accessibilityLabel("Settings")
        }
        .font(Tokens.TextRole.detail)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Tokens.Spacing.s)
        .frame(height: Tokens.Spacing.l)
    }
}
