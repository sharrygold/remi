import SwiftUI

/// The Links tab: Saved links and Watch later, with watched videos tucked away below.
struct LinksPane: View {
    @ObservedObject var store: LibraryStore
    let density: Density
    let space: Space?
    let showsSpace: Bool
    @Binding var list: LinkList
    @State private var showWatched = false
    @Environment(\.panelActions) private var actions

    var body: some View {
        VStack(spacing: 0) {
            picker
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: density.sectionGap) {
                    let items = store.links(in: space, list: list)
                    let pinned = items.filter(\.isPinned)
                    let others = items.filter { !$0.isPinned }
                    if items.isEmpty {
                        emptyState
                    } else {
                        if !pinned.isEmpty { group("Pinned", rows: pinned) }
                        if !others.isEmpty { group(pinned.isEmpty ? nil : list.title, rows: others) }
                    }
                    if list == .watchLater { watchedSection }
                }
                .padding(Tokens.Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .modifier(FollowSelection(proxy: proxy))
            }
        }
    }

    private var picker: some View {
        HStack(spacing: Tokens.Spacing.xs) {
            ForEach(LinkList.allCases, id: \.self) { item in
                let count = store.links(in: space, list: item).count
                Button { list = item } label: {
                    Label("\(item.title)\(count > 0 ? "  \(count)" : "")", systemImage: item.symbol)
                        .font(Tokens.TextRole.detail.weight(list == item ? .semibold : .regular))
                        .foregroundStyle(list == item ? .primary : .secondary)
                        .padding(.horizontal, Tokens.Spacing.s)
                        .padding(.vertical, Tokens.Spacing.xs)
                        .background(list == item ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(list == item ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.horizontal, Tokens.Spacing.m - Tokens.Spacing.xs)
        .padding(.top, Tokens.Spacing.s + Tokens.Spacing.xs)
    }

    private var emptyState: some View {
        VStack(spacing: Tokens.Spacing.s) {
            Image(systemName: list.symbol).font(.title2).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(list == .saved ? "No saved links yet" : "Nothing to watch").font(Tokens.TextRole.sectionTitle)
            Text(list == .saved ? "Paste a link above and press Return to keep it here."
                                : "Paste a YouTube or other video link above and it lands here.")
                .font(Tokens.TextRole.detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Tokens.Spacing.l * 2)
    }

    private func group(_ title: String?, rows: [LinkItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title).font(Tokens.TextRole.sectionTitle).foregroundStyle(.secondary).padding(.bottom, Tokens.Spacing.xs)
            }
            ForEach(rows) { LinkRowView(store: store, link: $0, density: density, showsSpace: showsSpace) }
        }
    }

    @ViewBuilder private var watchedSection: some View {
        let watched = store.links(in: space, list: .watchLater, watched: true)
        if !watched.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Button { withAnimation(Tokens.Motion.quick) { showWatched.toggle() } } label: {
                    Label("Watched (\(watched.count))", systemImage: showWatched ? "chevron.down" : "chevron.right")
                        .font(Tokens.TextRole.sectionTitle)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                if showWatched {
                    ForEach(watched) { LinkRowView(store: store, link: $0, density: density, showsSpace: showsSpace) }
                }
            }
        }
    }
}

struct LinkRowView: View {
    @ObservedObject var store: LibraryStore
    let link: LinkItem
    let density: Density
    let showsSpace: Bool
    @Environment(\.panelActions) private var actions
    @State private var hovering = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    private var isVideo: Bool { link.url.map(LinkClassifier.isVideo) ?? false }

    var body: some View {
        HStack(spacing: Tokens.Spacing.s) {
            if editing {
                // While renaming, the row is a text field rather than a button, so clicks go to the field.
                details
            } else {
                Button(action: open) { details.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .help(link.urlString)
                    .accessibilityLabel("\(link.title), \(link.domain)")
                    .accessibilityHint("Opens in your browser")
            }

            if link.isPinned {
                Image(systemName: "pin.fill").font(.caption).foregroundStyle(.tertiary).accessibilityLabel("Pinned")
            }
            if link.list == .watchLater {
                Button { store.setWatched(link, !link.isWatched) } label: {
                    Image(systemName: link.isWatched ? "arrow.uturn.backward" : "checkmark")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(hovering || link.isWatched ? 1 : 0.35)
                .help(link.isWatched ? "Back to Watch later" : "Mark as watched")
                .accessibilityLabel(link.isWatched ? "Mark \(link.title) as not watched" : "Mark \(link.title) as watched")
            }
        }
        .padding(.vertical, density.rowPadding)
        .keyboardHighlight(link.id)
        .id(link.id)
        .onHover { hovering = $0 }
        .contextMenu { menu }
        .onChange(of: actions.editRequest) { _, id in
            if id == link.id { startEditing() }
        }
    }

    private var details: some View {
        HStack(spacing: Tokens.Spacing.s) {
            LinkIcon(data: link.iconData, fallback: isVideo ? "play.rectangle.fill" : "globe")
            VStack(alignment: .leading, spacing: 1) {
                if editing {
                    TextField("Name", text: $draft)
                        .textFieldStyle(.plain)
                        .font(Tokens.TextRole.row)
                        .focused($fieldFocused)
                        .onSubmit(finishEditing)
                        .onExitCommand(perform: cancelEditing)
                        .onChange(of: fieldFocused) { _, focused in
                            if !focused { finishEditing() }
                        }
                        .onAppear { DispatchQueue.main.async { fieldFocused = true } }
                        .accessibilityLabel("Name for \(link.domain) link")
                } else {
                    Text(link.title).font(Tokens.TextRole.row).lineLimit(1)
                        .foregroundStyle(link.isWatched ? .secondary : .primary)
                }
                HStack(spacing: Tokens.Spacing.s) {
                    Text(link.domain).foregroundStyle(.secondary)
                    if showsSpace, let space = link.space {
                        Label(space.name, systemImage: space.symbol).foregroundStyle(space.tint)
                    }
                }
                .font(Tokens.TextRole.detail)
                .lineLimit(1)
            }
            Spacer(minLength: Tokens.Spacing.s)
        }
    }

    private func startEditing() {
        guard !editing else { return }
        draft = link.title
        editing = true
    }

    /// Return or clicking elsewhere keeps the name; Esc leaves it as it was.
    private func finishEditing() {
        guard editing else { return }
        editing = false
        store.rename(link, to: draft)
        actions.focusCapture()
    }

    private func cancelEditing() {
        guard editing else { return }
        editing = false
        actions.focusCapture()
    }

    private func open() {
        guard let url = link.url else { return }
        actions.open(.url(url))
    }

    @ViewBuilder private var menu: some View {
        Button("Open") { open() }
        Button("Rename…") { DispatchQueue.main.async { startEditing() } }
        Button("Copy Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(link.urlString, forType: .string)
        }
        Divider()
        if link.list == .saved {
            Button(link.isPinned ? "Unpin" : "Pin to Top") { store.setPinned(link, !link.isPinned) }
            Button("Move to Watch later") { store.move(link, to: .watchLater) }
        } else {
            Button(link.isWatched ? "Mark as Not Watched" : "Mark as Watched") { store.setWatched(link, !link.isWatched) }
            Button("Move to Saved links") { store.move(link, to: .saved) }
        }
        Menu("Move to Space") {
            ForEach(store.spaces) { space in
                Button(space.name) { store.move(link, to: space) }.disabled(space.id == link.space?.id)
            }
        }
        Divider()
        Button("Delete", role: .destructive) {
            store.delete(link)
            actions.confirm("Link deleted  ·  ⌘Z to undo")
        }
    }
}

/// The site's icon when fetched, otherwise a quiet symbol.
struct LinkIcon: View {
    let data: Data?
    let fallback: String

    var body: some View {
        Group {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().interpolation(.high)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Image(systemName: fallback).foregroundStyle(.secondary)
            }
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }
}
