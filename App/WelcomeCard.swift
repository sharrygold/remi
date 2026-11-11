import ServiceManagement
import SwiftUI

/// Open at login, shared by Settings and the welcome card.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns a message when macOS refused.
    @discardableResult
    static func set(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return "This works once the app is in your Applications folder."
        }
    }
}

/// Three short pages on first launch, also reachable from Settings > General.
struct WelcomeCard: View {
    @ObservedObject var widget: CompanionSettings
    let shortcut: String
    let onDone: () -> Void
    @State private var page = CommandLine.arguments.first { $0.hasPrefix("--preview-welcome-page=") }
        .flatMap { Int($0.dropFirst("--preview-welcome-page=".count)) } ?? 0
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginNote: String?

    private static let lastPage = 2
    private static let tricks = [
        ("#work", "Files it in a Space. A new name creates one."),
        ("today  fri", "Sets the due date. Day names go last."),
        ("!", "Marks it important."),
        ("every monday", "Repeats it. Also daily, weekly, monthly."),
        ("a link", "Saves to Links. Videos go to Watch later."),
        ("words + link", "A task that opens that link."),
        ("⌘Return", "Saves the line as a note instead."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                switch page {
                case 0: openPage
                case 1: typePage
                default: yoursPage
                }
            }
            .padding(Tokens.Spacing.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
    }

    private var openPage: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
            Text("Welcome to \(AppInfo.displayName)").font(.title3.weight(.semibold))
            Text("A little bird that remembers for you.").font(Tokens.TextRole.meta).foregroundStyle(.secondary)
            fact("Open it from anywhere", "Press \(shortcut), or click or pull your companion at the edge of the screen.")
            fact("Save the tab you're on", "Press \(HotKeyCombo.savedSaveTab.display) in your browser. It's saved without opening anything, and your companion reacts.")
            fact("Let things go", "Hover a task to delete it, and ⌘Z brings it back. Each morning you can keep or let go of what's left from before.")
        }
    }

    private var typePage: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s + 2) {
            Text("Say it all in one line").font(.title3.weight(.semibold))
            Text("Send invoice #work fri !").font(.footnote.monospaced())
                .padding(.horizontal, Tokens.Spacing.s)
                .padding(.vertical, Tokens.Spacing.xs)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: Tokens.Spacing.xs + 3) {
                ForEach(Self.tricks, id: \.0) { trick in
                    HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.s) {
                        Text(trick.0).font(.footnote.monospaced().weight(.medium)).frame(width: 96, alignment: .leading)
                        Text(trick.1).font(Tokens.TextRole.detail).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var yoursPage: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
            Text("Make it yours").font(.title3.weight(.semibold))
            choice("Companion") {
                Picker("Companion", selection: $widget.style) {
                    ForEach(CompanionStyle.allCases) { Text($0.title).tag($0) }
                }
            }
            choice("Plumage") {
                Picker("Plumage", selection: $widget.plumage) {
                    ForEach(Plumage.allCases) { Text($0.title).tag($0) }
                }
            }
            Toggle("Open at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                .tint(Color.brand)
                .font(Tokens.TextRole.detail)
            if let loginNote { Text(loginNote).font(Tokens.TextRole.detail).foregroundStyle(.secondary) }
        }
    }

    private func fact(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
            Text(title).font(Tokens.TextRole.sectionTitle)
            Text(detail).font(Tokens.TextRole.detail).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func choice<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
            Text(title).font(Tokens.TextRole.detail).foregroundStyle(.secondary)
            control().pickerStyle(.segmented).labelsHidden()
        }
    }

    private var footer: some View {
        HStack(spacing: Tokens.Spacing.s) {
            HStack(spacing: 5) {
                ForEach(0...Self.lastPage, id: \.self) { index in
                    Circle().fill(index == page ? AnyShapeStyle(Color.brand) : AnyShapeStyle(.quaternary)).frame(width: 6, height: 6)
                }
            }
            .accessibilityLabel("Page \(page + 1) of \(Self.lastPage + 1)")
            Spacer()
            if page > 0 {
                Button("Back") { page -= 1 }
                    .buttonStyle(.plain)
                    .font(Tokens.TextRole.detail)
                    .foregroundStyle(.secondary)
            }
            Button {
                if page < Self.lastPage { page += 1 } else { onDone() }
            } label: {
                Text(page < Self.lastPage ? "Next" : "Get Started")
                    .font(Tokens.TextRole.detail.weight(.semibold))
                    .foregroundStyle(Color.onBrand)
                    .padding(.horizontal, Tokens.Spacing.m)
                    .padding(.vertical, Tokens.Spacing.xs + 2)
                    .background(Color.brand, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(Tokens.Spacing.m)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        loginNote = LoginItem.set(on)
        launchAtLogin = LoginItem.isEnabled
    }
}
