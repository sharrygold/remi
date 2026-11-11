import SwiftUI

/// The Links tab: Saved links, Watch later and any lists you make, chosen from one menu so that any
/// number of them fits. Watched videos are tucked away below.
struct LinksPane: View {
    @ObservedObject var store: LibraryStore
    let density: Density
    let space: Space?
    let showsSpace: Bool
    @Binding var list: LinkList
    /// The custom list on show; nil for Saved links and Watch later.
    @Binding var groupID: UUID?
    /// Bumped from outside to open the Add link field.
    var addRequests = 0
    @State private var showWatched = false
    @State private var adding = false
    /// Naming a new list, or renaming the one on show.
    @State private var naming: Naming?
    @State private var namingSymbol = LinkGroup.defaultSymbol
    /// A link just added by hand, whose name field opens next.
    @State private var renameID: UUID?
    @Environment(\.panelActions) private var actions

    private enum Naming { case new, rename }

    /// What the menu switches between.
    private enum Shelf: Hashable {
        case list(LinkList)
        case group(UUID)
    }

    private var selectedGroup: LinkGroup? { store.linkGroups.first { $0.id == groupID } }

    private var shelf: Binding<Shelf> {
        Binding(get: { groupID.map(Shelf.group) ?? .list(list) }, set: { value in
            switch value {
            case .list(let item):
                groupID = nil
                list = item
            case .group(let id):
                list = .saved
                groupID = id
            }
        })
    }

    private var visibleLinks: [LinkItem] {
        groupID.map { store.links(in: space, group: $0) } ?? store.links(in: space, list: list)
    }

    var body: some View {
        VStack(spacing: 0) {
            picker
            if let naming {
                ListNamingCard(isRenaming: naming == .rename, name: naming == .rename ? selectedGroup?.name ?? "" : "",
                               symbol: $namingSymbol, onSave: saveName, onCancel: closeNaming)
                    .id(naming == .rename)
            }
            if adding {
                InlineAddField(placeholder: "Paste or type a link", symbol: "link", onSave: addLink, onClose: { closeAdding() })
            }
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: density.sectionGap) {
                    let items = visibleLinks
                    let pinned = items.filter(\.isPinned)
                    let others = items.filter { !$0.isPinned }
                    if items.isEmpty {
                        emptyState
                    } else {
                        if !pinned.isEmpty { group("Pinned", rows: pinned) }
                        if !others.isEmpty { group(pinned.isEmpty ? nil : shelfTitle, rows: others) }
                    }
                    if groupID == nil, list == .watchLater { watchedSection }
                }
                .padding(Tokens.Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .modifier(FollowSelection(proxy: proxy))
            }
        }
        .environment(\.panelActions, renameActions)
        .onChange(of: addRequests) { _, _ in adding = true }
        .onAppear {
            // For screenshots, after any list chosen at launch has settled.
            if CommandLine.arguments.contains("--preview-new-list") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { naming = .new }
            }
        }
        .onChange(of: list) { _, _ in adding = false }
        .onChange(of: groupID) { _, _ in
            adding = false
            naming = nil
        }
    }

    /// Passes the just-added link's rename request down to its row.
    private var renameActions: PanelActions {
        var copy = actions
        if let renameID { copy.editRequest = renameID }
        return copy
    }

    /// Saves to the list on screen, then opens the new link's name, since a bare address
    /// says little about why you kept it. Return keeps the page title, Esc too.
    private func addLink(_ text: String) -> Bool {
        guard let url = CaptureParser.parse(text, spaceNames: []).url else {
            actions.confirm("That doesn't look like a link")
            return false
        }
        let saved = store.addLink(url, list: list, group: selectedGroup, currentSpace: space)
        closeAdding(refocus: false)
        guard saved.isNew else {
            actions.confirm("Already in \(store.listTitle(saved.link))")
            actions.focusCapture()
            return true
        }
        actions.confirm("Saved to \(store.listTitle(saved.link))  ·  name it, or Esc")
        let id = saved.link.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            renameID = id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { renameID = nil }
        }
        return true
    }

    private func closeAdding(refocus: Bool = true) {
        adding = false
        if refocus { actions.focusCapture() }
    }

    private var shelfTitle: String { selectedGroup?.name ?? list.title }
    private var shelfSymbol: String { selectedGroup?.symbol ?? list.symbol }

    private func countLabel(_ title: String, _ count: Int) -> String { count > 0 ? "\(title)  (\(count))" : title }

    /// Lists are chosen from a menu, so any number of them leaves the Add button where it is.
    private var picker: some View {
        HStack(spacing: Tokens.Spacing.s) {
            Menu {
                Picker("List", selection: shelf) {
                    ForEach(LinkList.allCases, id: \.self) { item in
                        Label(countLabel(item.title, store.links(in: space, list: item).count), systemImage: item.symbol).tag(Shelf.list(item))
                    }
                    ForEach(store.linkGroups) { group in
                        Label(countLabel(group.name, store.links(in: space, group: group.id).count), systemImage: group.symbol).tag(Shelf.group(group.id))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                Divider()
                Button("New List…", systemImage: "plus") { startNaming(.new) }
                if let group = selectedGroup {
                    Button("Rename “\(group.name)”…") { startNaming(.rename) }
                    Button("Delete “\(group.name)”", role: .destructive) { deleteList(group) }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: shelfSymbol).foregroundStyle(.secondary)
                    Text(countLabel(shelfTitle, visibleLinks.count)).foregroundStyle(.primary).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                }
                .font(Tokens.TextRole.detail.weight(.semibold))
                .padding(.horizontal, Tokens.Spacing.s + 2)
                .padding(.vertical, Tokens.Spacing.xs + 1)
                .background(.quaternary, in: Capsule())
                .contentShape(Capsule())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .help("Choose a list, or make a new one (← and → switch)")
            .accessibilityLabel("List: \(shelfTitle)")
            .layoutPriority(-1)
            Spacer(minLength: Tokens.Spacing.s)
            AddButton(title: "Add link", help: "Add a link to \(shelfTitle)") { adding = true }
        }
        .padding(.leading, Tokens.Spacing.m - Tokens.Spacing.xs)
        .padding(.trailing, Tokens.Spacing.s)
        .padding(.top, Tokens.Spacing.s)
    }

    private func startNaming(_ kind: Naming) {
        // After the menu has closed, so the field can take the cursor.
        DispatchQueue.main.async {
            namingSymbol = kind == .rename ? selectedGroup?.symbol ?? LinkGroup.defaultSymbol : LinkGroup.defaultSymbol
            naming = kind
        }
    }

    private func closeNaming() {
        naming = nil
        actions.focusCapture()
    }

    /// Returns true when the name was used; a taken name leaves the field open to try again.
    private func saveName(_ text: String) -> Bool {
        if naming == .rename, let group = selectedGroup {
            guard store.rename(group, to: text, symbol: namingSymbol) else {
                actions.confirm("There's already a list with that name")
                return false
            }
        } else {
            guard let group = store.addLinkGroup(named: text, symbol: namingSymbol) else {
                actions.confirm("There's already a list with that name")
                return false
            }
            list = .saved
            groupID = group.id
            actions.confirm("Made “\(group.name)”  ·  right-click any link to move it here")
        }
        closeNaming()
        return true
    }

    private func deleteList(_ group: LinkGroup) {
        let name = group.name
        groupID = nil
        list = .saved
        store.delete(group)
        actions.confirm("Deleted “\(name)”, its links are in Saved links  ·  ⌘Z to undo")
    }

    private var emptyState: some View {
        VStack(spacing: Tokens.Spacing.s) {
            Image(systemName: shelfSymbol).font(.title2).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(selectedGroup != nil ? "Nothing in \(shelfTitle) yet" : list == .saved ? "No saved links yet" : "Nothing to watch")
                .font(Tokens.TextRole.sectionTitle)
            Text(selectedGroup != nil ? "Add one here, or right-click any link and move it to this list."
                 : list == .saved ? "Add one, or paste a link below and press Return."
                                  : "Paste a YouTube or other video link below and it lands here.")
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

/// Naming a list: its own card, so it can't be mistaken for part of the list behind it.
private struct ListNamingCard: View {
    let isRenaming: Bool
    @State var name: String
    @Binding var symbol: String
    /// Returns true when the name was used.
    let onSave: (String) -> Bool
    let onCancel: () -> Void
    @FocusState private var focused: Bool

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    private func save() {
        guard canSave else { return }
        _ = onSave(name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
            Text(isRenaming ? "Rename list" : "New list")
                .font(Tokens.TextRole.detail.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: Tokens.Spacing.s) {
                Image(systemName: symbol)
                    .foregroundStyle(Color.brand)
                    .frame(width: 22)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                TextField("List name", text: $name)
                    .brandTextInput()
                    .textFieldStyle(.plain)
                    .font(Tokens.TextRole.row)
                    .focused($focused)
                    .onSubmit(save)
                    .onExitCommand(perform: onCancel)
                    .onAppear { DispatchQueue.main.async { focused = true } }
                    .accessibilityLabel("List name")
            }
            .padding(.horizontal, Tokens.Spacing.s)
            .padding(.vertical, Tokens.Spacing.xs + 2)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: Tokens.Radius.small, style: .continuous))
            IconGrid(symbols: LibraryStore.linkGroupSymbols, selected: symbol) { symbol = $0 }
            HStack(spacing: Tokens.Spacing.m) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .font(Tokens.TextRole.detail)
                    .foregroundStyle(.secondary)
                Button(action: save) {
                    Text(isRenaming ? "Save" : "Create List")
                        .font(Tokens.TextRole.detail.weight(.semibold))
                        .foregroundStyle(Color.onBrand)
                        .padding(.horizontal, Tokens.Spacing.m - 3)
                        .padding(.vertical, Tokens.Spacing.xs + 2)
                        .background(Color.brand, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.45)
            }
        }
        .padding(Tokens.Spacing.s + 4)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.9), in: RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Tokens.Radius.medium, style: .continuous).strokeBorder(Color.brand.opacity(0.45), lineWidth: 1)
        }
        .padding(.horizontal, Tokens.Spacing.s)
        .padding(.top, Tokens.Spacing.s)
        .transition(.opacity)
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
                .brandTextInput()
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
        if !store.linkGroups.isEmpty {
            Menu("Move to List") {
                ForEach(store.linkGroups) { group in
                    Button(group.name) { store.move(link, to: group) }.disabled(group.id == link.groupID)
                }
                if link.groupID != nil {
                    Divider()
                    Button("Saved links") { store.move(link, to: .saved) }
                }
            }
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
