import AppKit
import ServiceManagement
import SwiftUI
import UserNotifications

/// What Settings needs from the app, handed over in one object.
final class SettingsContext: ObservableObject {
    let store: LibraryStore
    let widget: WidgetDebug
    let reminders: Reminders
    /// Where the library and its backups live; nil for an in-memory demo session.
    let libraryDirectory: URL?
    /// Registers a new global shortcut; false if macOS refused it.
    let applyHotKey: (HotKeyCombo) -> Bool
    @Published var tab: SettingsTab = .general
    /// True while the shortcut field waits for keys. Shared so the self-test can drive it.
    @Published var recordingShortcut = false
    /// The last recording's problem, if any.
    @Published var shortcutMessage: String?
    @Published var shortcut = HotKeyCombo.saved
    var showWelcome: () -> Void = {}
    private var keyMonitor: Any?

    init(store: LibraryStore, widget: WidgetDebug, reminders: Reminders, libraryDirectory: URL?, applyHotKey: @escaping (HotKeyCombo) -> Bool) {
        self.store = store
        self.widget = widget
        self.reminders = reminders
        self.libraryDirectory = libraryDirectory
        self.applyHotKey = applyHotKey
    }

    /// Takes the next key press from the app's event stream while recording. The current shortcut is
    /// switched off meanwhile, so it can be pressed and recorded too.
    func startRecording() {
        guard !recordingShortcut else { return }
        recordingShortcut = true
        shortcutMessage = nil
        _ = applyHotKey(HotKeyCombo(keyCode: -1, modifiers: 0, display: ""))
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {
                self.stopRecording(with: nil)
            } else if let combo = HotKeyCombo(event: event) {
                self.stopRecording(with: combo)
            } else {
                self.shortcutMessage = "Include ⌘, ⌥ or ⌃, for example ⌥Space."
            }
            return nil
        }
    }

    func stopRecording(with combo: HotKeyCombo?) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        recordingShortcut = false
        guard let combo else {
            _ = applyHotKey(shortcut)
            return
        }
        if applyHotKey(combo) {
            shortcut = combo
            combo.save()
            shortcutMessage = nil
        } else {
            _ = applyHotKey(shortcut)
            shortcutMessage = "macOS or another app already uses \(combo.display). Try another."
        }
    }

    func resetShortcut() {
        stopRecording(with: .standard)
    }
}

enum SettingsTab: String, CaseIterable {
    case general = "General", spaces = "Spaces", reminders = "Reminders", data = "Data", deleted = "Recently Deleted"

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .spaces: "square.grid.2x2"
        case .reminders: "bell"
        case .data: "externaldrive"
        case .deleted: "trash"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var context: SettingsContext

    /// A sidebar like System Settings. TabView put its tabs in a toolbar overflow on macOS 27.
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsTab.allCases, id: \.self) { item in
                    Button { context.tab = item } label: {
                        Label(item.rawValue, systemImage: item.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .foregroundStyle(context.tab == item ? Color.white : Color.primary)
                            .background(context.tab == item ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(context.tab == item ? .isSelected : [])
                }
                Spacer()
            }
            .padding(10)
            .frame(width: 190)
            .background(.background.secondary)
            Divider()
            page(context.tab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 700, height: 520)
    }

    @ViewBuilder private func page(_ tab: SettingsTab) -> some View {
        switch tab {
        case .general: GeneralSettings(context: context, widget: context.widget)
        case .spaces: SpacesSettings(store: context.store)
        case .reminders: ReminderSettings(reminders: context.reminders)
        case .data: DataSettings(context: context)
        case .deleted: DeletedSettings(store: context.store)
        }
    }
}

// MARK: General

private struct GeneralSettings: View {
    let context: SettingsContext
    @ObservedObject var widget: WidgetDebug
    @AppStorage(SettingsKey.autoTuck) private var autoTuck = true
    @AppStorage(SettingsKey.showCount) private var showCount = true
    @AppStorage(SettingsKey.hideFromRecordings) private var hideFromRecordings = true
    @AppStorage(SettingsKey.showOverFullScreen) private var showOverFullScreen = true
    @AppStorage(SettingsKey.clipboardNudge) private var clipboardNudge = true
    @AppStorage(SettingsKey.preferredBrowser) private var browser = ""
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginNote: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                if let loginNote { note(loginNote) }
                LabeledContent("Shortcut to open the panel") {
                    ShortcutField(context: context)
                }
                LabeledContent("First-time tips") {
                    Button("Show Welcome Again", action: context.showWelcome)
                }
            }
            Section("Links") {
                Picker("Open links in", selection: $browser) {
                    Text("Automatic (Dia, then Arc)").tag("")
                    ForEach(Browser.installed, id: \.id) { item in Text(item.name).tag(item.id) }
                    Text("System default").tag("system")
                }
                Toggle("Offer to save a link I've copied", isOn: $clipboardNudge)
            }
            Section("Widget") {
                Picker("Style", selection: $widget.prototype) {
                    ForEach(WidgetPrototype.allCases) { Text($0.title).tag($0) }
                }
                Picker("Colour", selection: $widget.colour) {
                    ForEach(WidgetColour.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Show today's task count", isOn: $showCount)
                Toggle("Tuck into the edge when idle", isOn: $autoTuck)
                Toggle("Show over full-screen apps", isOn: $showOverFullScreen)
            }
            Section("Privacy") {
                Toggle("Hide from screen recordings and screenshots", isOn: $hideFromRecordings)
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        loginNote = LoginItem.set(on)
        launchAtLogin = LoginItem.isEnabled
    }
}

private func note(_ text: String) -> some View {
    Text(text).font(.footnote).foregroundStyle(.secondary)
}

/// Browsers installed on this Mac, found by asking which apps open web links.
struct Browser {
    let id: String
    let name: String

    static var installed: [Browser] {
        guard let probe = URL(string: "https://example.com") else { return [] }
        var seen = Set<String>()
        return NSWorkspace.shared.urlsForApplications(toOpen: probe).compactMap { url -> Browser? in
            guard let id = Bundle(url: url)?.bundleIdentifier, seen.insert(id).inserted else { return nil }
            return Browser(id: id, name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// Click, then press the new shortcut. Esc cancels.
private struct ShortcutField: View {
    @ObservedObject var context: SettingsContext

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                Button(context.recordingShortcut ? "Press keys…" : context.shortcut.display) {
                    context.recordingShortcut ? context.stopRecording(with: nil) : context.startRecording()
                }
                .monospaced()
                .help(context.recordingShortcut ? "Press the shortcut, or Esc to cancel" : "Click, then press the shortcut you want")
                if context.shortcut != .standard, !context.recordingShortcut {
                    Button("Reset", action: context.resetShortcut)
                }
            }
            if let message = context.shortcutMessage { note(message) }
        }
        .onDisappear { if context.recordingShortcut { context.stopRecording(with: nil) } }
    }
}

// MARK: Spaces

private struct SpacesSettings: View {
    @ObservedObject var store: LibraryStore
    @State private var newName = ""
    @State private var deleting: Space?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                ForEach(store.spaces) { space in
                    SpaceRow(store: store, space: space, deleting: $deleting)
                }
                .onMove { source, destination in
                    var ordered = store.spaces
                    ordered.move(fromOffsets: source, toOffset: destination)
                    store.reorderSpaces(ordered)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: false))
            HStack {
                TextField("New Space", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
            note("Drag to reorder. In the capture bar, #name files an item in a Space, and a new #name creates one.")
                .padding([.horizontal, .bottom])
        }
    }

    private func add() {
        if store.addSpace(named: newName) != nil { newName = "" }
    }
}

private struct SpaceRow: View {
    @ObservedObject var store: LibraryStore
    let space: Space
    @Binding var deleting: Space?
    @State private var name = ""
    @State private var showLook = false
    @State private var target: UUID?

    private var isDeleting: Bool { deleting?.id == space.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button { showLook = true } label: {
                    Image(systemName: space.symbol).foregroundStyle(space.tint).frame(width: 22)
                }
                .buttonStyle(.borderless)
                .help("Change symbol and colour")
                .popover(isPresented: $showLook) { LookPicker(store: store, space: space) }
                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .onSubmit(commitName)
                    .onAppear { name = space.name }
                    .onChange(of: space.name) { _, new in name = new }
                Text("\(store.itemCount(in: space))").foregroundStyle(.secondary).monospacedDigit()
                    .help("Items in this Space")
                Button { deleting = isDeleting ? nil : space } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                    .disabled(store.spaces.count < 2)
                    .accessibilityLabel("Delete \(space.name)")
            }
            if isDeleting { deleteRow }
        }
        .padding(.vertical, 2)
    }

    private var deleteRow: some View {
        let others = store.spaces.filter { $0.id != space.id }
        return HStack {
            Picker("Move its items to", selection: Binding(get: { target ?? others.first?.id }, set: { target = $0 })) {
                ForEach(others) { Text($0.name).tag(Optional($0.id)) }
            }
            .fixedSize()
            Spacer()
            Button("Cancel") { deleting = nil }
            Button("Delete Space", role: .destructive) {
                guard let destination = others.first(where: { $0.id == (target ?? others.first?.id) }) else { return }
                deleting = nil
                store.deleteSpace(space, movingItemsTo: destination)
            }
        }
        .font(.callout)
        .padding(.leading, 30)
    }

    private func commitName() {
        if !store.rename(space, to: name) { name = space.name }
    }
}

private struct LookPicker: View {
    @ObservedObject var store: LibraryStore
    let space: Space

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(28)), count: 8), spacing: 8) {
                ForEach(LibraryStore.spaceSymbols, id: \.self) { symbol in
                    Button { store.setLook(space, symbol: symbol) } label: {
                        Image(systemName: symbol)
                            .frame(width: 28, height: 28)
                            .background(symbol == space.symbol ? space.tint.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(symbol)
                }
            }
            HStack(spacing: 10) {
                ForEach(LibraryStore.spaceTints, id: \.self) { tint in
                    Button { store.setLook(space, tint: tint) } label: {
                        Circle().fill(Tokens.Tint.named(tint)).frame(width: 20, height: 20)
                            .overlay { if tint == space.tintName { Circle().stroke(.primary, lineWidth: 2).padding(-3) } }
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Colour \(tint)")
                }
            }
        }
        .padding()
    }
}

// MARK: Reminders

private struct ReminderSettings: View {
    let reminders: Reminders
    @AppStorage(SettingsKey.reminders) private var enabled = true
    @AppStorage(SettingsKey.reminderMinutes) private var minutes = 9 * 60
    @State private var status: UNAuthorizationStatus = .notDetermined

    private var time: Binding<Date> {
        Binding(get: {
            Calendar.current.date(byAdding: .minute, value: minutes, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            minutes = (parts.hour ?? 9) * 60 + (parts.minute ?? 0)
        })
    }

    var body: some View {
        Form {
            Section {
                Toggle("Remind me on a task's due date", isOn: $enabled)
                DatePicker("At", selection: time, displayedComponents: .hourAndMinute)
                    .disabled(!enabled)
            } footer: {
                note("Tasks without a due date never remind you. Ticking a task cancels its reminder.")
            }
            Section("Permission") {
                switch status {
                case .authorized, .provisional, .ephemeral:
                    Label("Notifications are allowed", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                    Button("Send Test Reminder") { reminders.sendTest() }
                        .help("Shows a reminder in five seconds")
                case .denied:
                    Text("Notifications are turned off for this app in System Settings.")
                    Button("Open Notification Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                default:
                    Text("macOS asks once before reminders can appear.")
                    Button("Allow Notifications…") { reminders.requestPermission { _ in refresh() } }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        .onChange(of: enabled) { _, _ in reminders.reschedule() }
        .onChange(of: minutes) { _, _ in reminders.reschedule() }
    }

    private func refresh() {
        reminders.status { status = $0 }
    }
}

// MARK: Data

private struct DataSettings: View {
    let context: SettingsContext
    @State private var message: String?
    @State private var lastBackup: String?

    private var backupsDirectory: URL? { context.libraryDirectory.map(Backups.directory(in:)) }

    var body: some View {
        Form {
            Section {
                LabeledContent("Export everything") {
                    Button("Export…", action: export)
                }
                LabeledContent("Restore or merge from an export") {
                    Button("Import…", action: importFile)
                }
            } footer: {
                note("Export writes a JSON file (which Import reads) and a Markdown copy you can read anywhere.")
            }
            Section {
                LabeledContent("Daily backups") {
                    HStack {
                        Button("Back Up Now", action: backUpNow)
                        Button("Show in Finder") {
                            guard let backupsDirectory else { return }
                            try? FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(backupsDirectory)
                        }
                    }
                    .disabled(backupsDirectory == nil)
                }
                if let lastBackup { note(lastBackup) }
            } footer: {
                note("One backup a day is kept in Application Support. The last \(Backups.keep) are kept.")
            }
            if let message {
                Section { Text(message) }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshLastBackup)
    }

    private func refreshLastBackup() {
        guard let backupsDirectory, let newest = Backups.list(in: backupsDirectory).first else {
            lastBackup = nil
            return
        }
        lastBackup = "Latest: \(newest.deletingPathExtension().lastPathComponent)"
    }

    private func export() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose a folder for the export"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let archive = context.store.makeArchive()
        let day = Backups.fileName(for: Date()).replacingOccurrences(of: "Backup ", with: "").replacingOccurrences(of: ".json", with: "")
        let base = "\(AppInfo.displayName) export \(day)"
        let json = folder.appendingPathComponent(base + ".json")
        let markdown = folder.appendingPathComponent(base + ".md")
        do {
            try LibraryArchive.encoder().encode(archive).write(to: json, options: .atomic)
            try ArchiveMarkdown.render(archive, appName: AppInfo.displayName).write(to: markdown, atomically: true, encoding: .utf8)
            message = "Exported \(archive.tasks.count) tasks, \(archive.notes.count) notes and \(archive.links.count) links."
            NSWorkspace.shared.activateFileViewerSelecting([json, markdown])
        } catch {
            message = "The export couldn't be written to that folder. Try another one."
        }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.prompt = "Import"
        panel.message = "Choose an export or backup file"
        guard panel.runModal() == .OK, let file = panel.url else { return }
        guard let data = try? Data(contentsOf: file), let archive = try? LibraryArchive.decode(data) else {
            message = "That file isn't an export from \(AppInfo.displayName)."
            return
        }
        let alert = NSAlert()
        alert.messageText = "Import \(archive.tasks.count) tasks, \(archive.notes.count) notes and \(archive.links.count) links?"
        alert.informativeText = "Items you already have are kept, and the newer copy of each wins. A backup of your current library is made first."
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if let backupsDirectory {
            _ = try? Backups.backUp({ context.store.makeArchive() }, to: backupsDirectory, force: true)
        }
        let summary = context.store.importArchive(archive)
        message = "Imported: \(summary.added) added, \(summary.updated) updated, \(summary.unchanged) already up to date."
        refreshLastBackup()
    }

    private func backUpNow() {
        guard let backupsDirectory else { return }
        do {
            try Backups.backUp({ context.store.makeArchive() }, to: backupsDirectory, force: true)
            message = "Backed up."
        } catch {
            message = "The backup couldn't be written."
        }
        refreshLastBackup()
    }
}

// MARK: Recently deleted

private struct DeletedSettings: View {
    @ObservedObject var store: LibraryStore
    @State private var items: [DeletedItem] = []

    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "trash").font(.title2).foregroundStyle(.secondary)
                    Text("Nothing recently deleted").font(.headline)
                    note("Deleted tasks, notes and links stay here for \(LibraryStore.keepDeletedDays) days.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(items) { item in
                    HStack {
                        Image(systemName: symbol(item)).foregroundStyle(.secondary).frame(width: 20)
                        VStack(alignment: .leading) {
                            Text(item.title).lineLimit(1)
                            note(detail(item))
                        }
                        Spacer()
                        Button("Restore") { store.restore(item); refresh() }
                        Button { store.deleteForever(item); refresh() } label: { Image(systemName: "xmark.bin") }
                            .buttonStyle(.borderless)
                            .help("Delete now")
                            .accessibilityLabel("Delete \(item.title) now")
                    }
                }
                HStack {
                    note("Items are removed for good after \(LibraryStore.keepDeletedDays) days.")
                    Spacer()
                    Button("Delete All Now…", role: .destructive, action: emptyAll)
                }
                .padding()
            }
        }
        .onAppear(perform: refresh)
    }

    private func refresh() { items = store.deletedItems() }

    private func symbol(_ item: DeletedItem) -> String {
        switch item {
        case .task: "checklist"
        case .note: "note.text"
        case .link: "link"
        }
    }

    private func detail(_ item: DeletedItem) -> String {
        let days = Calendar.current.dateComponents([.day], from: item.deletedAt, to: Date()).day ?? 0
        let left = max(LibraryStore.keepDeletedDays - days, 0)
        let when = days == 0 ? "Deleted today" : "Deleted \(days) day\(days == 1 ? "" : "s") ago"
        return [item.kind, item.spaceName, "\(when) · \(left) days left"].compactMap { $0 }.joined(separator: " · ")
    }

    private func emptyAll() {
        let alert = NSAlert()
        alert.messageText = "Delete \(items.count) items now?"
        alert.informativeText = "They can't be restored afterwards, except from a backup."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        items.forEach(store.deleteForever)
        refresh()
    }
}
