import Foundation
import SwiftData

extension LibraryStore {
    /// Pinned first, then newest. Watched videos are kept apart in their own list.
    func links(in space: Space?, list: LinkList, watched: Bool = false) -> [LinkItem] {
        links.filter { ($0.list == list) && (space == nil || $0.space?.id == space?.id) && $0.isWatched == watched }
            .sorted { lhs, rhs in
                if watched { return (lhs.watchedAt ?? .distantPast) > (rhs.watchedAt ?? .distantPast) }
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                return lhs.createdAt > rhs.createdAt
            }
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
    func addLink(_ url: URL, list: LinkList? = nil, spaceMatch: ParsedCapture.SpaceMatch = .none,
                 currentSpace: Space?) -> (link: LinkItem, isNew: Bool) {
        if let existing = existingLink(for: url) { return (existing, false) }
        let (space, createdSpace) = resolveSpace(spaceMatch, currentSpace: currentSpace)
        let link = LinkItem(url: url, list: list ?? LinkClassifier.list(for: url), space: space)
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
        let previous = (link.list, link.isWatched, link.watchedAt)
        change(link, {
            $0.list = list
            $0.isWatched = false
            $0.watchedAt = nil
        }, undo: {
            $0.list = previous.0
            $0.isWatched = previous.1
            $0.watchedAt = previous.2
        })
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
