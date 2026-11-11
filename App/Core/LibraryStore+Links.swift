import Foundation
import SwiftData

extension LibraryStore {
    /// Pinned first, then newest. Watched videos are kept apart in their own list.
    func links(in space: Space?, list: LinkList, watched: Bool = false) -> [LinkItem] {
        links.filter { $0.groupID == nil && ($0.list == list) && (space == nil || $0.space?.id == space?.id) && $0.isWatched == watched }
            .sorted { lhs, rhs in
                if watched { return (lhs.watchedAt ?? .distantPast) > (rhs.watchedAt ?? .distantPast) }
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                return lhs.createdAt > rhs.createdAt
            }
    }

    /// Pinned first, then newest.
    func links(in space: Space?, group id: UUID) -> [LinkItem] {
        links.filter { $0.groupID == id && (space == nil || $0.space?.id == space?.id) }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                return lhs.createdAt > rhs.createdAt
            }
    }

    /// The name of the list a link is in, for messages.
    func listTitle(_ link: LinkItem) -> String {
        linkGroups.first { $0.id == link.groupID }?.name ?? link.list.title
    }

    func watchLaterCount(in space: Space? = nil) -> Int {
        links(in: space, list: .watchLater).count
    }

    func existingLink(for url: URL) -> LinkItem? {
        let key = LinkClassifier.normalized(url)
        return links.first { $0.url.map(LinkClassifier.normalized) == key }
    }

    /// True when the URL is already a saved link or a task's action, so the clipboard nudge stays quiet.
    func isSaved(_ url: URL) -> Bool {
        if existingLink(for: url) != nil { return true }
        let key = LinkClassifier.normalized(url)
        return tasks.contains { task in
            if case .url(let target) = task.action { return LinkClassifier.normalized(target) == key }
            return false
        }
    }

    /// Saves a link, or returns the one already saved for that address with `isNew` false.
    @discardableResult
    func addLink(_ url: URL, list: LinkList? = nil, group: LinkGroup? = nil, spaceMatch: ParsedCapture.SpaceMatch = .none,
                 currentSpace: Space?) -> (link: LinkItem, isNew: Bool) {
        if let existing = existingLink(for: url) { return (existing, false) }
        let (space, createdSpace) = resolveSpace(spaceMatch, currentSpace: currentSpace)
        let link = LinkItem(url: url, list: group != nil ? .saved : list ?? LinkClassifier.list(for: url), space: space)
        link.groupID = group?.id
        context.insert(link)
        commit { [context] in
            context.delete(link)
            if let createdSpace { context.delete(createdSpace) }
        }
        onLinkAdded?(link)
        return (link, true)
    }

    /// Fills in what the page says about itself. Not undoable; it is not something you did.
    /// The first title wins: a saved tab's own title beats a later fetch, which may hit a bot check.
    func setMetadata(for id: UUID, title: String?, iconData: Data?) {
        guard let link = links.first(where: { $0.id == id }) else { return }
        if !link.titleEdited, !link.titleFetched, let title, !title.trimmingCharacters(in: .whitespaces).isEmpty {
            link.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let iconData { link.iconData = iconData }
        link.titleFetched = true
        save()
        objectWillChange.send()
    }

    private func change(_ link: LinkItem, _ apply: (LinkItem) -> Void, undo: @escaping (LinkItem) -> Void) {
        apply(link)
        link.updatedAt = Date()
        commit {
            undo(link)
            link.updatedAt = Date()
        }
    }

    /// Your own name for the link. A blank name is ignored.
    func rename(_ link: LinkItem, to title: String) {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = (link.title, link.titleEdited)
        guard !cleaned.isEmpty, cleaned != previous.0 else { return }
        change(link, {
            $0.title = cleaned
            $0.titleEdited = true
        }, undo: {
            $0.title = previous.0
            $0.titleEdited = previous.1
        })
    }

    func setPinned(_ link: LinkItem, _ pinned: Bool) {
        let previous = link.isPinned
        change(link, { $0.isPinned = pinned }, undo: { $0.isPinned = previous })
    }

    func setWatched(_ link: LinkItem, _ watched: Bool, now: Date = Date()) {
        let previous = (link.isWatched, link.watchedAt)
        change(link, {
            $0.isWatched = watched
            $0.watchedAt = watched ? now : nil
        }, undo: {
            $0.isWatched = previous.0
            $0.watchedAt = previous.1
        })
    }

    func move(_ link: LinkItem, to list: LinkList) {
        let previous = (link.list, link.isWatched, link.watchedAt, link.groupID)
        change(link, {
            $0.list = list
            $0.isWatched = false
            $0.watchedAt = nil
            $0.groupID = nil
        }, undo: {
            $0.list = previous.0
            $0.isWatched = previous.1
            $0.watchedAt = previous.2
            $0.groupID = previous.3
        })
    }

    func move(_ link: LinkItem, to group: LinkGroup) {
        let previous = (link.list, link.isWatched, link.watchedAt, link.groupID)
        change(link, {
            $0.list = .saved
            $0.isWatched = false
            $0.watchedAt = nil
            $0.groupID = group.id
        }, undo: {
            $0.list = previous.0
            $0.isWatched = previous.1
            $0.watchedAt = previous.2
            $0.groupID = previous.3
        })
    }

    // MARK: Custom lists

    private func isListNameFree(_ name: String, ignoring group: LinkGroup? = nil) -> Bool {
        let key = CaptureParser.normalized(name)
        let taken = LinkList.allCases.map(\.title) + linkGroups.filter { $0.id != group?.id }.map(\.name)
        return !taken.contains { CaptureParser.normalized($0) == key }
    }

    /// Nil when the name is blank or already used by another list.
    @discardableResult
    func addLinkGroup(named name: String) -> LinkGroup? {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, isListNameFree(cleaned) else { return nil }
        let group = LinkGroup(name: cleaned, sortOrder: (linkGroups.map(\.sortOrder).max() ?? -1) + 1)
        context.insert(group)
        commit { [context] in context.delete(group) }
        return group
    }

    /// False when the name is blank or already used by another list.
    @discardableResult
    func rename(_ group: LinkGroup, to name: String) -> Bool {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, isListNameFree(cleaned, ignoring: group) else { return false }
        let previous = group.name
        group.name = cleaned
        group.updatedAt = Date()
        commit {
            group.name = previous
            group.updatedAt = Date()
        }
        return true
    }

    /// Removes the list and moves its links to Saved links; nothing in it is lost.
    func delete(_ group: LinkGroup) {
        let members = links.filter { $0.groupID == group.id }
        let (id, name, order, created) = (group.id, group.name, group.sortOrder, group.createdAt)
        for link in members { link.groupID = nil }
        context.delete(group)
        commit { [context] in
            let restored = LinkGroup(name: name, sortOrder: order)
            restored.id = id
            restored.createdAt = created
            context.insert(restored)
            for link in members { link.groupID = id }
        }
    }

    func move(_ link: LinkItem, to space: Space) {
        let previous = link.space
        change(link, { $0.space = space }, undo: { $0.space = previous })
    }

    /// Moves to Recently deleted; permanent removal arrives in M5.
    func delete(_ link: LinkItem, now: Date = Date()) {
        change(link, { $0.deletedAt = now }, undo: { $0.deletedAt = nil })
    }
}
