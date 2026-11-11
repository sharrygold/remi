import Combine
import Foundation
import UserNotifications

/// Due-date reminders through Notification Center, at the chosen time on the due day.
/// Everything is rebuilt from the task list whenever it changes, which keeps the logic simple.
final class Reminders: NSObject, UNUserNotificationCenterDelegate {
    /// macOS keeps at most 64 pending; the soonest are scheduled.
    static let limit = 60
    private static let prefix = "task-"
    private let store: LibraryStore
    private let center = UNUserNotificationCenter.current()
    private var watching: AnyCancellable?
    var onOpen: (() -> Void)?

    init(store: LibraryStore) {
        self.store = store
        super.init()
        center.delegate = self
    }

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: SettingsKey.reminders) }

    func start() {
        watching = store.$tasks
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.reschedule() }
        guard Self.isEnabled else { return }
        center.getNotificationSettings { [weak self] settings in
            if settings.authorizationStatus == .notDetermined { self?.requestPermission() }
        }
        reschedule()
    }

    /// Shows macOS's one-time Allow prompt.
    func requestPermission(then done: ((Bool) -> Void)? = nil) {
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.reschedule()
                done?(granted)
            }
        }
    }

    func status(_ done: @escaping (UNAuthorizationStatus) -> Void) {
        center.getNotificationSettings { settings in
            DispatchQueue.main.async { done(settings.authorizationStatus) }
        }
    }

    /// When each open task's reminder fires: the due day at the chosen time, if that is still ahead.
    static func fireDates(for tasks: [TaskItem], minutes: Int, now: Date = Date(), calendar: Calendar = .current) -> [(TaskItem, Date)] {
        tasks.compactMap { task -> (TaskItem, Date)? in
            guard !task.isCompleted, !task.isSetAside, !task.isPaused, task.deletedAt == nil, let due = task.dueDate else { return nil }
            let day = calendar.startOfDay(for: due)
            guard let fire = calendar.date(byAdding: .minute, value: minutes, to: day), fire > now else { return nil }
            return (task, fire)
        }
        .sorted { $0.1 < $1.1 }
        .prefix(limit)
        .map { $0 }
    }

    func reschedule() {
        let minutes = UserDefaults.standard.integer(forKey: SettingsKey.reminderMinutes)
        let planned = Self.isEnabled ? Self.fireDates(for: store.tasks, minutes: minutes) : []
        let requests = planned.map { task, fire -> UNNotificationRequest in
            let content = UNMutableNotificationContent()
            content.title = task.title
            content.body = task.space.map { "Due today · \($0.name)" } ?? "Due today"
            content.sound = .default
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            return UNNotificationRequest(identifier: Self.prefix + task.id.uuidString, content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        }
        center.getPendingNotificationRequests { [center] pending in
            let ours = pending.map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)
            requests.forEach { center.add($0) }
        }
    }

    /// A reminder in five seconds, so the user can see that notifications arrive.
    func sendTest() {
        let content = UNMutableNotificationContent()
        content.title = "Reminders are working"
        content.body = "Tasks with a due date will remind you like this."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "test-\(UUID().uuidString)", content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false))
        center.add(request)
    }

    func pendingCount(_ done: @escaping (Int) -> Void) {
        center.getPendingNotificationRequests { pending in
            DispatchQueue.main.async { done(pending.filter { $0.identifier.hasPrefix(Self.prefix) }.count) }
        }
    }

    // Show the banner even though the app counts as running, and open the panel when it is clicked.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { self.onOpen?() }
        completionHandler()
    }
}
