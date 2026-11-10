import Foundation

/// Every preference key in one place. Values live in UserDefaults; Settings edits them with @AppStorage
/// and the app reacts to `UserDefaults.didChangeNotification`.
enum SettingsKey {
    static let autoTuck = "autoTuck"
    static let showCount = "showBadge"
    static let hideFromRecordings = "hideFromRecordings"
    static let showOverFullScreen = "showOverFullScreen"
    static let reminders = "remindersEnabled"
    /// Minutes after midnight on the due day.
    static let reminderMinutes = "reminderMinutes"
    static let hotKeyCode = "hotKeyCode"
    static let hotKeyModifiers = "hotKeyModifiers"
    static let hotKeyDisplay = "hotKeyDisplay"
    static let clipboardNudge = ClipboardNudge.preferenceKey
    static let preferredBrowser = LinkOpener.preferenceKey

    /// Defaults agreed in Phase 0: tuck on, count shown, hidden from recordings, reminders on at 09:00, ⌃Space.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            autoTuck: true,
            showCount: true,
            hideFromRecordings: true,
            showOverFullScreen: true,
            reminders: true,
            reminderMinutes: 9 * 60,
            clipboardNudge: true,
            hotKeyCode: HotKeyCombo.standard.keyCode,
            hotKeyModifiers: HotKeyCombo.standard.modifiers,
            hotKeyDisplay: HotKeyCombo.standard.display,
        ])
    }
}
