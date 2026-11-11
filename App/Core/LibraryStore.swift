import Combine
import Foundation
import SwiftData

/// The one place Spaces, tasks and notes are read and changed. The UI only talks to this, on the main thread.
final class LibraryStore: ObservableObject {
    static let lingerSeconds: TimeInterval = 1.2
    private static let symbols = ["folder", "star", "leaf", "flag", "bolt", "heart"]
    private static let tints = ["work", "green", "personal", "learning", "teal"]

    @Published private(set) var spaces: [Space] = []
    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var notes: [Note] = []
    @Published private(set) var links: [LinkItem] = []
    @Published private(set) var linkGroups: [LinkGroup] = []
    /// Called after a link is saved, so the app can fetch its title and icon. Keeps this file free of networking.
    var onLinkAdded: ((LinkItem) -> Void)?
    /// A task was captured, by any route. The companion reacts to these.
    var onTaskAdded: ((TaskItem) -> Void)?
    /// A task was ticked off.
    var onTaskCompleted: ((TaskItem) -> Void)?
    /// True when the saved data could not be opened and this session is temporary.
    private(set) var isTemporary = false
    /// Where the library is saved; nil when it lives in memory.
    private(set) var directory: URL?

    let context: ModelContext
    private var undoStack: [() -> Void] = []
    /// Typing in a note saves after a short pause rather than on every key.
    private var pendingSave: DispatchWorkItem?

    var canUndo: Bool { !undoStack.isEmpty }

    /// `directory` nil keeps everything in memory, for tests and demos.
    init(directory: URL?) {
        let schema = Schema([Space.self, TaskItem.self, Note.self, LinkItem.self, LinkGroup.self])
        var container: ModelContainer?
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("Library.store"))
            container = try? ModelContainer(for: schema, configurations: configuration)
        }
        if container == nil { isTemporary = directory != nil } else { self.directory = directory }
        let resolved = container ?? (try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        context = ModelContext(resolved)
        seedSpacesIfNeeded()
        removeBlankNotes()
        reload()
    }

    /// Follows the bundle ID rather than the display name. Debug builds keep their own folder,
    /// so development runs can never touch real data or look like an existing library.
    static var defaultDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var name = Bundle.main.bundleIdentifier ?? "io.github.sharrygold.remi"
        #if DEBUG
        name += ".debug"
        #endif
        return support.appendingPathComponent(name, isDirectory: true)
    }

    private func seedSpacesIfNeeded() {
        guard ((try? context.fetchCount(FetchDescriptor<Space>())) ?? 0) == 0 else { return }
        let starters = [("Work", "building.2", "work"), ("Personal", "house", "personal"), ("Learning", "book", "learning")]
        for (index, starter) in starters.enumerated() {
            context.insert(Space(name: starter.0, symbol: starter.1, tintName: starter.2, sortOrder: index))
        }
        save()
    }

    func reload() {
        spaces = (try? context.fetch(FetchDescriptor<Space>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        let all = (try? context.fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        tasks = all.filter { $0.deletedAt == nil }
        let allNotes = (try? context.fetch(FetchDescriptor<Note>())) ?? []
        notes = allNotes.filter { $0.deletedAt == nil }
        let allLinks = (try? context.fetch(FetchDescriptor<LinkItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
        links = allLinks.filter { $0.deletedAt == nil }
        linkGroups = (try? context.fetch(FetchDescriptor<LinkGroup>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
    }

    func save() {
        pendingSave?.cancel()
        pendingSave = nil
        try? context.save()
    }

    func scheduleSave(after delay: TimeInterval = 0.6) {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func commit(undo: @escaping () -> Void) {
        undoStack.append(undo)
        save()
        reload()
    }

    func clearUndo() {
        undoStack.removeAll()
    }

    func undo() {
        guard let action = undoStack.popLast() else { return }
        action()
        save()
        reload()
    }

    // MARK: Capture

    /// Used when nothing is typed and "All" is selected, so every task still belongs to a Space.
    var fallbackSpace: Space? { spaces.first { $0.name == "Personal" } ?? spaces.first }

    @discardableResult
    func add(_ parsed: ParsedCapture, currentSpace: Space?) -> TaskItem? {
        guard parsed.canSave else { return nil }
        let (space, createdSpace) = resolveSpace(parsed.space, currentSpace: currentSpace)
        let order = (tasks.map(\.sortOrder).min() ?? 0) - 1
        let task = TaskItem(title: parsed.title, space: space, dueDate: parsed.due, isImportant: parsed.important, sortOrder: order)
        if let url = parsed.url { task.action = .url(url) }
        task.repeatRule = parsed.repeatRule
        context.insert(task)
        commit { [context] in
            context.delete(task)
            if let createdSpace { context.delete(createdSpace) }
        }
        onTaskAdded?(task)
        return task
    }

    /// Resolves the Space a capture belongs to, creating a new one when `#name` asked for it.
    func resolveSpace(_ match: ParsedCapture.SpaceMatch, currentSpace: Space?) -> (space: Space?, created: Space?) {
        switch match {
        case .existing(let name):
            return (spaces.first { $0.name == name }, nil)
        case .new(let name):
            let created = makeSpace(named: name)
            return (created, created)
        case .none:
            return (currentSpace ?? fallbackSpace, nil)
        }
    }

    private func makeSpace(named name: String) -> Space {
        let index = spaces.count
        let space = Space(name: name, symbol: Self.symbols[index % Self.symbols.count],
                          tintName: Self.tints[index % Self.tints.count], sortOrder: (spaces.map(\.sortOrder).max() ?? -1) + 1)
        context.insert(space)
        return space
    }

    // MARK: Editing

    func change(_ task: TaskItem, _ apply: (TaskItem) -> Void, undo: @escaping (TaskItem) -> Void) {
        apply(task)
        task.updatedAt = Date()
        commit {
            undo(task)
            task.updatedAt = Date()
        }
    }

    func toggleCompleted(_ task: TaskItem, now: Date = Date()) {
        if !task.isCompleted, task.repeatRule != nil {
            completeRepeating(task, now: now)
            return
        }
        let wasCompleted = task.isCompleted, previousDate = task.completedAt
        change(task, {
            $0.isCompleted = !wasCompleted
            $0.completedAt = wasCompleted ? nil : now
        }, undo: {
            $0.isCompleted = wasCompleted
            $0.completedAt = previousDate
        })
        if !wasCompleted { onTaskCompleted?(task) }
    }

    func rename(_ task: TaskItem, to title: String) {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = task.title
        guard !cleaned.isEmpty, cleaned != previous else { return }
        change(task, { $0.title = cleaned }, undo: { $0.title = previous })
    }

    func setImportant(_ task: TaskItem, _ important: Bool) {
        let previous = task.isImportant
        change(task, { $0.isImportant = important }, undo: { $0.isImportant = previous })
    }

    func setDue(_ task: TaskItem, _ date: Date?) {
        let previous = task.dueDate
        change(task, { $0.dueDate = date }, undo: { $0.dueDate = previous })
    }

    func setAction(_ task: TaskItem, _ action: ItemAction?) {
        let previous = task.action
        change(task, { $0.action = action }, undo: { $0.action = previous })
    }

    func move(_ task: TaskItem, to space: Space) {
        let previous = task.space
        change(task, { $0.space = space }, undo: { $0.space = previous })
    }

    /// Moves to Recently deleted; permanent removal arrives in M5.
    func delete(_ task: TaskItem, now: Date = Date()) {
        change(task, { $0.deletedAt = now }, undo: { $0.deletedAt = nil })
    }

    /// Applies a new order to the tasks in `ordered`, reusing the sort slots they already had.
    func reorder(_ ordered: [TaskItem]) {
        let previous = ordered.map(\.sortOrder)
        let slots = previous.sorted()
        for (task, slot) in zip(ordered, slots) { task.sortOrder = slot }
        commit {
            for (task, slot) in zip(ordered, previous) { task.sortOrder = slot }
        }
    }

    // MARK: Lists

    /// Just-ticked tasks stay listed for a moment so the tick can be seen before they fade.
    private func isOpen(_ task: TaskItem, now: Date) -> Bool {
        guard !task.isSetAside, !task.isPaused else { return false }
        guard task.isCompleted, let completed = task.completedAt else { return !task.isCompleted }
        return now.timeIntervalSince(completed) < Self.lingerSeconds
    }

    private func inSpace(_ task: TaskItem, _ space: Space?) -> Bool {
        space == nil || task.space?.id == space?.id
    }

    func dueToday(in space: Space? = nil, now: Date = Date(), calendar: Calendar = .current) -> [TaskItem] {
        tasks.filter { task in
            guard let due = task.dueDate else { return false }
            return isOpen(task, now: now) && inSpace(task, space) && calendar.isDate(due, inSameDayAs: now)
        }
    }

    func overdue(in space: Space? = nil, now: Date = Date(), calendar: Calendar = .current) -> [TaskItem] {
        let today = calendar.startOfDay(for: now)
        return tasks.filter { task in
            guard let due = task.dueDate else { return false }
            return isOpen(task, now: now) && inSpace(task, space) && due < today
        }
    }

    func open(in space: Space? = nil, now: Date = Date()) -> [TaskItem] {
        tasks.filter { isOpen($0, now: now) && inSpace($0, space) }
    }

    /// Finished today, newest first. Older finished tasks leave the lists but stay in search, exports and backups.
    func doneToday(in space: Space? = nil, now: Date = Date(), calendar: Calendar = .current) -> [TaskItem] {
        done(in: space, now: now).filter { $0.completedAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false }
    }

    func done(in space: Space? = nil, now: Date = Date()) -> [TaskItem] {
        tasks.filter { $0.isCompleted && !isOpen($0, now: now) && inSpace($0, space) }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    /// Today's tasks are all done, and there were some.
    func allKeptToday(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        todayOpenCount(now: now, calendar: calendar) == 0 && tasks.contains { task in
            guard task.isCompleted, let due = task.dueDate else { return false }
            return calendar.isDate(due, inSameDayAs: now)
        }
    }

    /// The number the widget shows: open tasks due today, never counting ticked ones.
    func todayOpenCount(now: Date = Date(), calendar: Calendar = .current) -> Int {
        tasks.filter { task in
            guard let due = task.dueDate else { return false }
            return !task.isCompleted && !task.isSetAside && !task.isPaused && calendar.isDate(due, inSameDayAs: now)
        }.count
    }
}
