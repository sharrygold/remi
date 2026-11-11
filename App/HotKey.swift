import AppKit
import Carbon.HIToolbox

/// A key and modifiers in the form Carbon's hot key API takes, plus how to show it.
struct HotKeyCombo: Equatable {
    var keyCode: Int
    var modifiers: Int
    var display: String

    static let standard = HotKeyCombo(keyCode: kVK_Space, modifiers: controlKey, display: "⌃Space")
    static let saveTabStandard = HotKeyCombo(keyCode: kVK_ANSI_S, modifiers: controlKey | optionKey, display: "⌃⌥S")

    static var saved: HotKeyCombo {
        let defaults = UserDefaults.standard
        return HotKeyCombo(keyCode: defaults.integer(forKey: SettingsKey.hotKeyCode),
                           modifiers: defaults.integer(forKey: SettingsKey.hotKeyModifiers),
                           display: defaults.string(forKey: SettingsKey.hotKeyDisplay) ?? standard.display)
    }

    static var savedSaveTab: HotKeyCombo {
        let defaults = UserDefaults.standard
        return HotKeyCombo(keyCode: defaults.integer(forKey: SettingsKey.saveTabKeyCode),
                           modifiers: defaults.integer(forKey: SettingsKey.saveTabModifiers),
                           display: defaults.string(forKey: SettingsKey.saveTabDisplay) ?? saveTabStandard.display)
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(keyCode, forKey: SettingsKey.hotKeyCode)
        defaults.set(modifiers, forKey: SettingsKey.hotKeyModifiers)
        defaults.set(display, forKey: SettingsKey.hotKeyDisplay)
    }

    func saveAsSaveTab() {
        let defaults = UserDefaults.standard
        defaults.set(keyCode, forKey: SettingsKey.saveTabKeyCode)
        defaults.set(modifiers, forKey: SettingsKey.saveTabModifiers)
        defaults.set(display, forKey: SettingsKey.saveTabDisplay)
    }

    func sameKeys(as other: HotKeyCombo) -> Bool { keyCode == other.keyCode && modifiers == other.modifiers }

    /// Nil unless the press includes ⌘, ⌥ or ⌃ (or is a function key), so plain typing is never taken.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let code = Int(event.keyCode)
        let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]
        guard !flags.intersection([.command, .option, .control]).isEmpty || functionKeys.contains(code) else { return nil }
        var carbon = 0
        var symbols = ""
        if flags.contains(.control) { carbon |= controlKey; symbols += "⌃" }
        if flags.contains(.option) { carbon |= optionKey; symbols += "⌥" }
        if flags.contains(.shift) { carbon |= shiftKey; symbols += "⇧" }
        if flags.contains(.command) { carbon |= cmdKey; symbols += "⌘" }
        self.init(keyCode: code, modifiers: carbon, display: symbols + Self.name(for: event))
    }

    init(keyCode: Int, modifiers: Int, display: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.display = display
    }

    private static func name(for event: NSEvent) -> String {
        let names: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_Escape: "⎋",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let name = names[Int(event.keyCode)] { return name }
        return (event.charactersIgnoringModifiers ?? "?").uppercased()
    }
}

/// A system-wide shortcut through Carbon, which needs no Accessibility permission.
final class HotKey {
    /// One Carbon handler serves every shortcut, and the pressed shortcut's ID says whose it is.
    private static var live: [UInt32: HotKey] = [:]
    private static var handler: EventHandlerRef?

    private var reference: EventHotKeyRef?
    private let id: UInt32
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        id = UInt32(Self.live.count + 1)
        Self.live[id] = self
        Self.installHandlerIfNeeded()
    }

    private static func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var pressed = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            if status == noErr { HotKey.live[pressed.id]?.action() }
            return noErr
        }, 1, &spec, nil, &handler)
    }

    /// Returns false when macOS refuses the combination, for example if another app owns it.
    /// A key code below zero just switches the shortcut off.
    func register(_ combo: HotKeyCombo) -> Bool {
        unregister()
        guard combo.keyCode >= 0 else { return true }
        let hotKeyID = EventHotKeyID(signature: OSType(0x50524348), id: id)
        return RegisterEventHotKey(UInt32(combo.keyCode), UInt32(combo.modifiers), hotKeyID, GetApplicationEventTarget(), 0, &reference) == noErr
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
    }
}
