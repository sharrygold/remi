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

/// Three short steps on first launch, also reachable from Settings > General.
struct WelcomeCard: View {
    @ObservedObject var widget: WidgetDebug
    let shortcut: String
    let onDone: () -> Void
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Spacing.m + 2) {
                    Text("Welcome to \(AppInfo.displayName)").font(.title3.weight(.semibold))

                    step(1, "Open it from anywhere") {
                        Text("Press \(Text(shortcut).fontWeight(.semibold)), or click or pull your companion at the edge of the screen.")
                    }

                    step(2, "Type what's on your mind") {
                        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                            Text("Send invoice #work today !").font(.footnote.monospaced())
                                .padding(.horizontal, Tokens.Spacing.s)
                                .padding(.vertical, 3)
                                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            Text("A Space, a due date and “important”, all in one line. Return saves a task, ⌘Return saves a note, and a pasted link goes to Links.")
                        }
                    }

                    step(3, "Make it yours") {
                        VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
                            Picker("Companion", selection: $widget.prototype) {
                                ForEach(WidgetPrototype.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            Toggle("Open at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                            if let loginNote { Text(loginNote).foregroundStyle(.secondary) }
                        }
                    }
                }
                .padding(Tokens.Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button(action: onDone) {
                    Text("Get Started")
                        .font(Tokens.TextRole.detail.weight(.semibold))
                        .padding(.horizontal, Tokens.Spacing.m)
                        .padding(.vertical, Tokens.Spacing.xs + 2)
                        .background(Color.accentColor.opacity(0.16), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            .padding(Tokens.Spacing.m)
        }
    }

    private func step<Detail: View>(_ number: Int, _ title: String, @ViewBuilder detail: () -> Detail) -> some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.s + 2) {
            Text("\(number)")
                .font(Tokens.TextRole.detail.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(.quaternary, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                Text(title).font(Tokens.TextRole.sectionTitle)
                detail().font(Tokens.TextRole.detail).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        loginNote = LoginItem.set(on)
        launchAtLogin = LoginItem.isEnabled
    }
}
