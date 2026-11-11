import Foundation
import SwiftData

/// Repeating tasks, the morning review and setting tasks aside.
///
/// The idea throughout: an unfinished list should never become a pile. Repeating tasks keep one
/// copy that rolls forward; old tasks can be let go without deleting them; and a fresh start
/// clears the deck in one step.
extension LibraryStore {
    /// A repeating task skipped this long pauses itself and asks once whether to keep it.
    static let pauseAfterDays = 14

    // MARK: Repeating

    func setRepeat(_ task: TaskItem, _ rule: RepeatRule?, now: Date = Date(), calendar: Calendar = .current) {
        let previous = (task.repeatName, task.dueDate, task.skippedSince, task.isPaused)
        change(task, {
            $0.repeatRule = rule
            if rule != nil, $0.dueDate == nil { $0.dueDate = calendar.startOfDay(for: now) }
            $0.skippedSince = nil
            $0.isPaused = false
        }, undo: {
            $0.repeatName = previous.0
            $0.dueDate = previous.1
            $0.skippedSince = previous.2
            $0.isPaused = previous.3
        })
    }

    /// Ticking a repeating task files this copy under Done and makes the next one.
    func completeRepeating(_ task: TaskItem, now: Date = Date(), calendar: Calendar = .current) {
        guard let rule = task.repeatRule else { return }
        let today = calendar.startOfDay(for: now)
        let due = task.dueDate ?? today
        var nextDate = rule.next(after: due, calendar: calendar)
        while nextDate <= today { nextDate = rule.next(after: nextDate, calendar: calendar) }

        let next = TaskItem(title: task.title, space: task.space, dueDate: nextDate, isImportant: task.isImportant, sortOrder: task.sortOrder)
        next.notes = task.notes
        next.actionKind = task.actionKind
        next.actionTarget = task.actionTarget
        next.repeatRule = rule
        context.insert(next)

        let previous = (task.repeatName, task.skippedSince)
        task.isCompleted = true
        task.completedAt = now
        task.repeatName = nil
        task.skippedSince = nil
        task.updatedAt = now
        commit { [context] in
            context.delete(next)
            task.isCompleted = false
            task.completedAt = nil
            task.repeatName = previous.0
            task.skippedSince = previous.1
            task.updatedAt = Date()
        }
        onTaskCompleted?(task)
    }

    /// Moves missed repeating tasks to their next date instead of letting them become overdue.
    /// Run at launch, when the day changes and when the panel opens. Not undoable: it is the
    /// calendar moving, not something you did.
    @discardableResult
    func rollForwardRepeating(now: Date = Date(), calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: now)
        var moved = 0
        for task in tasks where task.repeatRule != nil && !task.isCompleted && !task.isPaused && !task.isSetAside {
            guard let rule = task.repeatRule, let due = task.dueDate, due < today else { continue }
            var next = due
            while next < today { next = rule.next(after: next, calendar: calendar) }
            task.skippedSince = task.skippedSince ?? due
            task.dueDate = next
            if let since = task.skippedSince,
               (calendar.dateComponents([.day], from: since, to: today).day ?? 0) >= Self.pauseAfterDays {
                task.isPaused = true
            }
            task.updatedAt = now
            moved += 1
        }
        if moved > 0 {
            save()
            objectWillChange.send()
        }
        return moved
    }

    /// Repeating tasks that paused themselves, waiting for a keep-or-let-go answer.
    func pausedRepeating() -> [TaskItem] {
        tasks.filter { $0.isPaused && !$0.isSetAside && !$0.isCompleted }
    }

    func keepRepeating(_ task: TaskItem, now: Date = Date(), calendar: Calendar = .current) {
        let previous = (task.isPaused, task.skippedSince, task.dueDate)
        change(task, {
            $0.isPaused = false
            $0.skippedSince = nil
            if let rule = $0.repeatRule, let due = $0.dueDate, due < calendar.startOfDay(for: now) {
                var next = due
                while next < calendar.startOfDay(for: now) { next = rule.next(after: next, calendar: calendar) }
                $0.dueDate = next
            }
        }, undo: {
            $0.isPaused = previous.0
            $0.skippedSince = previous.1
            $0.dueDate = previous.2
        })
    }

    // MARK: Morning review

    /// One-off tasks dated before today and still open: what the morning review asks about.
    func leftFromBefore(now: Date = Date(), calendar: Calendar = .current) -> [TaskItem] {
        let today = calendar.startOfDay(for: now)
        return tasks.filter { task in
            guard let due = task.dueDate, task.repeatRule == nil else { return false }
            return !task.isCompleted && !task.isSetAside && !task.isPaused && due < today
        }
        .sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
    }

    /// "Later": keeps the task but takes its date away, so it waits in Tasks without nagging.
    func moveToLater(_ task: TaskItem) {
        setDue(task, nil)
    }

    // MARK: Setting aside

    /// Lets tasks go in one undoable step. They leave every list but stay in search and Set aside.
    func setAside(_ items: [TaskItem], now: Date = Date()) {
        guard !items.isEmpty else { return }
        let previous = items.map { ($0, $0.setAsideAt, $0.isPaused) }
        for task in items {
            task.setAsideAt = now
            task.isPaused = false
            task.updatedAt = now
        }
        commit {
            for (task, date, paused) in previous {
                task.setAsideAt = date
                task.isPaused = paused
                task.updatedAt = Date()
            }
        }
    }

    func bringBack(_ task: TaskItem, now: Date = Date(), calendar: Calendar = .current) {
        let previous = (task.setAsideAt, task.dueDate, task.skippedSince)
        change(task, {
            $0.setAsideAt = nil
            $0.skippedSince = nil
            // An old date would drop it straight back into the review.
            if let due = $0.dueDate, due < calendar.startOfDay(for: now) {
                $0.dueDate = $0.repeatRule.map { rule in
                    var next = due
                    while next < calendar.startOfDay(for: now) { next = rule.next(after: next, calendar: calendar) }
                    return next
                }
            }
        }, undo: {
            $0.setAsideAt = previous.0
            $0.dueDate = previous.1
            $0.skippedSince = previous.2
        })
    }

    /// Newest first.
    func setAsideTasks(in space: Space? = nil) -> [TaskItem] {
        tasks.filter { $0.isSetAside && (space == nil || $0.space?.id == space?.id) }
            .sorted { ($0.setAsideAt ?? .distantPast) > ($1.setAsideAt ?? .distantPast) }
    }

    /// Fresh start: every open task in the Space is set aside, as one undoable step.
    func freshStart(in space: Space? = nil, now: Date = Date()) -> Int {
        let open = tasks.filter { !$0.isCompleted && !$0.isSetAside && (space == nil || $0.space?.id == space?.id) }
        setAside(open, now: now)
        return open.count
    }
}
