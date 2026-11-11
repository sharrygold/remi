import SwiftUI

/// The strip at the top of every list: what you are looking at on the left, and the way to add
/// something by hand on the right. It stays put while the list scrolls.
struct PaneHeader<Leading: View>: View {
    let addTitle: String
    var addHelp: String?
    let onAdd: () -> Void
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: Tokens.Spacing.s) {
            leading
            Spacer(minLength: Tokens.Spacing.s)
            AddButton(title: addTitle, help: addHelp, action: onAdd)
        }
        .padding(.leading, Tokens.Spacing.m)
        .padding(.trailing, Tokens.Spacing.s)
        .padding(.top, Tokens.Spacing.s)
        .frame(minHeight: 36)
    }
}

/// "+ New task" and friends: a small tinted pill, so it reads as a button and not as a list row.
struct AddButton: View {
    let title: String
    var help: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "plus")
                .labelStyle(AddLabelStyle())
                .font(Tokens.TextRole.detail.weight(.semibold))
                .foregroundStyle(Color.brand)
                .padding(.horizontal, Tokens.Spacing.s + 2)
                .padding(.vertical, Tokens.Spacing.xs + 1)
                .background(Color.brand.opacity(hovering ? 0.18 : 0.11), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovering = $0 }
        .help(help ?? title)
    }
}

private struct AddLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

/// A one-line field that appears at the top of a list to add an item by hand.
/// Return saves and leaves the field open for the next one; Esc, or clicking away with
/// nothing typed, closes it.
struct InlineAddField: View {
    let placeholder: String
    let symbol: String
    /// Returns true when the text was saved, so the field clears for the next item.
    let onSave: (String) -> Bool
    let onClose: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Tokens.Spacing.s) {
            Image(systemName: symbol).foregroundStyle(.tertiary).accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .brandTextInput()
                .textFieldStyle(.plain)
                .font(Tokens.TextRole.row)
                .focused($focused)
                .onSubmit {
                    if text.trimmingCharacters(in: .whitespaces).isEmpty {
                        onClose()
                    } else if onSave(text) {
                        text = ""
                    }
                    focused = true
                }
                .onExitCommand(perform: onClose)
                .onChange(of: focused) { _, isFocused in
                    guard !isFocused else { return }
                    if !text.trimmingCharacters(in: .whitespaces).isEmpty, onSave(text) { text = "" }
                    onClose()
                }
                .onAppear { DispatchQueue.main.async { focused = true } }
                .accessibilityLabel(placeholder)
        }
        .padding(.horizontal, Tokens.Spacing.m)
        .padding(.vertical, Tokens.Spacing.s)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Tokens.Radius.small, style: .continuous))
        .padding(.horizontal, Tokens.Spacing.s)
        .padding(.top, Tokens.Spacing.xs)
        .transition(.opacity)
    }
}
