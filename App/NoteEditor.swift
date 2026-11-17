import AppKit
import SwiftUI

/// The note editor: a native text view that styles light Markdown as you type, saving as it goes.
struct NoteEditor: NSViewRepresentable {
    let note: Note
    let store: LibraryStore
    var onEscape: () -> Void
    var onOpenLink: (URL) -> Void
    var onConfirm: (String) -> Void

    func makeCoordinator() -> NoteEditorController {
        NoteEditorController(note: note, store: store)
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.onEscape = onEscape
        context.coordinator.onOpenLink = onOpenLink
        context.coordinator.onConfirm = onConfirm
        return context.coordinator.scrollView
    }

    func updateNSView(_ view: NSScrollView, context: Context) {
        context.coordinator.onEscape = onEscape
        context.coordinator.onOpenLink = onOpenLink
        context.coordinator.onConfirm = onConfirm
    }

    static func dismantleNSView(_ view: NSScrollView, coordinator: NoteEditorController) {
        coordinator.flush()
    }
}

/// Draws a Reminders-style circle in place of the checkbox character.
final class CheckboxAttachment: NSTextAttachment {
    let isChecked: Bool

    init(checked: Bool) {
        isChecked = checked
        super.init(data: nil, ofType: nil)
        let font = NoteStyle.body
        let size = round(font.pointSize * 1.1)
        let colours: [NSColor] = checked ? [.onBrand, .brand] : [.tertiaryLabelColor]
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: colours))
        let image = NSImage(systemSymbolName: checked ? "checkmark.circle.fill" : "circle",
                            accessibilityDescription: checked ? "Checked" : "Unchecked")?
            .withSymbolConfiguration(configuration) ?? NSImage()
        let cell = CheckboxCell(imageCell: image)
        cell.baseline = font.descender + 1
        attachmentCell = cell
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    static func string(checked: Bool) -> NSAttributedString {
        NSAttributedString(attachment: CheckboxAttachment(checked: checked))
    }
}

private final class CheckboxCell: NSTextAttachmentCell {
    var baseline: CGFloat = 0
    override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: baseline) }
    override func cellSize() -> NSSize {
        let size = image?.size ?? .zero
        return NSSize(width: size.width + 1, height: size.height)
    }
}

/// Font and spacing roles for notes, read from the system type scale.
enum NoteStyle {
    static var body: NSFont { .preferredFont(forTextStyle: .body) }
    static func heading(_ level: Int) -> NSFont {
        switch level {
        case 1: bold(.title2)
        case 2: bold(.title3)
        default: bold(.headline)
        }
    }
    static var title: NSFont { heading(1) }

    private static func bold(_ style: NSFont.TextStyle) -> NSFont {
        let font = NSFont.preferredFont(forTextStyle: style)
        return NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
    }

    static func paragraph(headIndent: CGFloat = 0) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        style.paragraphSpacing = Tokens.Spacing.xs
        style.headIndent = headIndent
        return style
    }
}

final class NoteTextView: NSTextView {
    var onEscape: (() -> Void)?
    var onToggleCheckbox: ((Int) -> Void)?
    var onCommand: ((String, NSEvent.ModifierFlags) -> Bool)?
    var onMakeTask: ((String) -> Void)?
    /// Pictures pasted or dropped, with where a drop landed. Returns false to paste the usual way.
    var onImages: (([(data: Data, points: CGSize?)], Int?) -> Bool)?
    /// The note's Markdown for part of the text, so copying keeps checkboxes and pictures.
    var markdownFor: ((NSRange) -> String)?
    var focusOnAppear = true
    let placeholder = "Start typing. The first line becomes the title."

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard focusOnAppear, let window else { return }
        focusOnAppear = false
        DispatchQueue.main.async { window.makeFirstResponder(self) }
    }

    /// Esc closes the find bar first, then leaves the note (instead of offering word completions).
    override func cancelOperation(_ sender: Any?) {
        if enclosingScrollView?.isFindBarVisible == true {
            finderAction(.hideFindInterface)
            window?.makeFirstResponder(self)
            return
        }
        onEscape?()
    }

    func finderAction(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        performTextFinderAction(item)
    }

    /// The pasteboard ⌘V reads; a self-test points it at a private one so the real clipboard is untouched.
    var pasteSource: NSPasteboard = .general

    override func paste(_ sender: Any?) {
        if let images = NoteImageFile.images(on: pasteSource), onImages?(images, nil) == true { return }
        super.paste(sender)
    }

    /// A plain-text view greys out Paste when the clipboard holds only a picture, so ⌘V never reached
    /// paste(_:). Pictures count as something to paste here.
    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(paste(_:)), NoteImageFile.images(on: pasteSource) != nil { return isEditable }
        return super.validateUserInterfaceItem(item)
    }

    // Pictures dropped from Finder, a browser or a screenshot thumbnail.
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        super.acceptableDragTypes + [.png, .tiff, .fileURL]
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        NoteImageFile.images(on: sender.draggingPasteboard) != nil ? .copy : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        NoteImageFile.images(on: sender.draggingPasteboard) != nil ? .copy : super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if let images = NoteImageFile.images(on: sender.draggingPasteboard) {
            let index = characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil))
            return onImages?(images, index) ?? false
        }
        return super.performDragOperation(sender)
    }

    /// AppKit may ask for plain text by its old name (NSStringPboardType) rather than `.string`;
    /// both are the same text, and missing the old name left the clipboard empty after ⌘C.
    static func isPlainText(_ type: NSPasteboard.PasteboardType) -> Bool {
        type == .string || type.rawValue == "NSStringPboardType"
    }

    /// Copies as the note's Markdown, so pasting into another note keeps checkboxes and pictures.
    /// A single picture on its own is copied as the picture too.
    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard Self.isPlainText(type), let markdownFor else { return super.writeSelection(to: pboard, type: type) }
        let range = selectedRange()
        guard range.length > 0 else { return false }
        return pboard.setString(markdownFor(range), forType: .string)
    }

    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
        let range = selectedRange()
        if range.length == 1, textStorage?.attribute(.attachment, at: range.location, effectiveRange: nil) is ImageAttachment {
            return [.string, .tiff]
        }
        return super.writablePasteboardTypes
    }

    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard types.contains(where: Self.isPlainText) else { return super.writeSelection(to: pboard, types: types) }
        pboard.clearContents()
        let range = selectedRange()
        var wrote = writeSelection(to: pboard, type: .string)
        if types.contains(.tiff), range.length == 1,
           let image = (textStorage?.attribute(.attachment, at: range.location, effectiveRange: nil) as? ImageAttachment)?.picture,
           let tiff = image.tiffRepresentation {
            wrote = pboard.setData(tiff, forType: .tiff) || wrote
        }
        return wrote
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if onCommand?(key, flags) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    /// Right-clicking a checkbox line offers to copy it to Tasks.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let index = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        let text = string as NSString
        guard index <= text.length else { return menu }
        let line = text.substring(with: text.lineRange(for: NSRange(location: index, length: 0))).trimmingCharacters(in: .newlines)
        guard let title = NoteText.checkboxText(ofEditorLine: line) else { return menu }
        let item = NSMenuItem(title: "Make Task", action: #selector(makeTask(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = title
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
        return menu
    }

    @objc private func makeTask(_ sender: NSMenuItem) {
        if let title = sender.representedObject as? String { onMakeTask?(title) }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = checkboxIndex(at: point) {
            onToggleCheckbox?(index)
            return
        }
        super.mouseDown(with: event)
    }

    func checkboxIndex(at point: NSPoint) -> Int? {
        guard let layoutManager, let textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layoutManager.glyphIndex(for: local, in: textContainer)
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
        guard rect.insetBy(dx: -3, dy: -3).contains(local) else { return nil }
        let index = layoutManager.characterIndexForGlyph(at: glyph)
        guard index < storage.length, storage.attribute(.attachment, at: index, effectiveRange: nil) is CheckboxAttachment else { return nil }
        return index
    }

    /// Where a checkbox is drawn, in this view's coordinates. Used by the self-test to click it.
    func checkboxRect(at index: Int) -> NSRect? {
        guard let layoutManager, let textContainer else { return nil }
        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        return rect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        let padding = textContainer?.lineFragmentPadding ?? 0
        let origin = NSPoint(x: textContainerOrigin.x + padding, y: textContainerOrigin.y)
        (placeholder as NSString).draw(at: origin, withAttributes: [.font: NoteStyle.title, .foregroundColor: NSColor.placeholderTextColor])
    }
}

/// Owns one note's text view: loading, Markdown shortcuts, styling and saving.
final class NoteEditorController: NSObject, NSTextViewDelegate {
    let scrollView = NSScrollView()
    let textView: NoteTextView
    var onEscape: (() -> Void)?
    var onOpenLink: ((URL) -> Void)?
    var onConfirm: ((String) -> Void)?
    private let note: Note
    private let store: LibraryStore
    /// True while this controller makes its own edits, so the shortcut rules don't run on them.
    private var applying = false

    /// The note open in the panel, if any. Panel keys use it for ⌘F and Esc.
    static weak var current: NoteEditorController?

    init(note: Note, store: LibraryStore) {
        self.note = note
        self.store = store
        // TextKit 1 keeps attachment hit-testing and paragraph styling simple and reliable.
        textView = NoteTextView(usingTextLayoutManager: false)
        super.init()
        configure()
        load()
        Self.current = self
    }

    /// True when the keyboard is in this note's text or its find bar.
    func hasFocus(in window: NSWindow) -> Bool {
        guard textView.window === window, let responder = window.firstResponder else { return false }
        if responder === textView { return true }
        let view = ((responder as? NSTextView)?.delegate as? NSView) ?? (responder as? NSView)
        return view?.isDescendant(of: scrollView) ?? false
    }

    var isFindBarVisible: Bool { scrollView.isFindBarVisible }

    func hideFind() {
        textView.finderAction(.hideFindInterface)
        textView.window?.makeFirstResponder(textView)
    }

    private func configure() {
        textView.delegate = self
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.textContainerInset = NSSize(width: Tokens.Spacing.m - 5, height: Tokens.Spacing.m)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.insertionPointColor = .brand
        textView.selectedTextAttributes = [.backgroundColor: NSColor.brand.withAlphaComponent(0.3)]
        textView.linkTextAttributes = [.foregroundColor: NSColor.brand, .underlineStyle: NSUnderlineStyle.single.rawValue,
                                       .cursor: NSCursor.pointingHand]
        textView.setAccessibilityLabel("Note")
        textView.onEscape = { [weak self] in self?.onEscape?() }
        textView.onToggleCheckbox = { [weak self] index in self?.toggleCheckbox(at: index) }
        textView.onCommand = { [weak self] key, flags in self?.command(key, flags) ?? false }
        textView.onMakeTask = { [weak self] title in self?.makeTask(title) }
        textView.onImages = { [weak self] images, index in self?.insertImages(images, at: index) ?? false }
        textView.markdownFor = { [weak self] range in self?.markdown(in: range) ?? "" }
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
    }

    private func load() {
        let (text, attachments) = NoteText.editorContent(fromMarkdown: note.body)
        textView.textStorage?.setAttributedString(attributed(text, attachments: attachments))
        restyle()
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        textView.undoManager?.removeAllActions()
    }

    /// Builds editor text, putting a checkbox or a picture wherever the object replacement character appears.
    func attributed(_ text: String, attachments: [NoteText.Attachment]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var remaining = attachments[...]
        var run = ""
        for character in text {
            guard character == NoteText.checkboxCharacter else {
                run.append(character)
                continue
            }
            result.append(NSAttributedString(string: run))
            run = ""
            switch remaining.popFirst() ?? .checkbox(checked: false) {
            case .checkbox(let checked): result.append(CheckboxAttachment.string(checked: checked))
            case .image(let name): result.append(ImageAttachment.string(name: name, url: store.noteImageURL(name)))
            }
        }
        result.append(NSAttributedString(string: run))
        return result
    }

    /// What each attachment character in a stretch of the text stands for.
    private func attachments(in range: NSRange) -> [NoteText.Attachment] {
        guard let storage = textView.textStorage else { return [] }
        var found: [NoteText.Attachment] = []
        let text = storage.string as NSString
        for index in range.location..<NSMaxRange(range) where text.character(at: index) == 0xFFFC {
            switch storage.attribute(.attachment, at: index, effectiveRange: nil) {
            case let image as ImageAttachment: found.append(.image(name: image.name))
            case let box as CheckboxAttachment: found.append(.checkbox(checked: box.isChecked))
            default: found.append(.checkbox(checked: false))
            }
        }
        return found
    }

    var markdown: String {
        guard let storage = textView.textStorage else { return note.body }
        return markdown(in: NSRange(location: 0, length: storage.length))
    }

    func markdown(in range: NSRange) -> String {
        NoteText.markdown(fromEditor: string.substring(with: range), attachments: attachments(in: range))
    }

    /// Images in the order they appear, for sharing.
    var imageURLs: [URL] {
        attachments(in: NSRange(location: 0, length: string.length)).compactMap {
            if case .image(let name) = $0 { store.noteImageURL(name) } else { nil }
        }
    }

    // MARK: Pictures

    /// Each picture goes on a line of its own, at the cursor or where it was dropped.
    func insertImages(_ images: [(data: Data, points: CGSize?)], at index: Int?) -> Bool {
        let names = images.compactMap { NoteImageFile.save($0.data, points: $0.points, in: store.noteImagesFolder) }
        guard !names.isEmpty else {
            onConfirm?("Couldn't read that picture")
            return true
        }
        let range = index.map { NSRange(location: min($0, string.length), length: 0) } ?? textView.selectedRange()
        let insertion = NSMutableAttributedString()
        if range.location > 0, string.character(at: range.location - 1) != 0x0A { insertion.append(NSAttributedString(string: "\n")) }
        for (offset, name) in names.enumerated() {
            if offset > 0 { insertion.append(NSAttributedString(string: "\n")) }
            insertion.append(ImageAttachment.string(name: name, url: store.noteImageURL(name)))
        }
        let end = NSMaxRange(range)
        if end >= string.length || string.character(at: end) != 0x0A { insertion.append(NSAttributedString(string: "\n")) }
        replace(range, with: insertion)
        textView.window?.makeFirstResponder(textView)
        return true
    }

    /// A line starting with a picture is a plain line, not a checkbox, though both use the same character.
    private func kind(of line: String, at location: Int) -> NoteText.LineKind {
        let kind = NoteText.kind(ofEditorLine: line)
        guard case .checkbox = kind else { return kind }
        let index = location + (NoteText.splitIndent(line).indent as NSString).length
        return textView.textStorage?.attribute(.attachment, at: index, effectiveRange: nil) is ImageAttachment ? .plain : kind
    }

    // MARK: Find and share

    func showFind() {
        textView.window?.makeFirstResponder(textView)
        textView.finderAction(.showFindInterface)
    }

    /// The note as readable text, then its pictures.
    var sharingItems: [Any] {
        [NoteText.plainText(fromMarkdown: markdown) as NSString] + imageURLs.filter { FileManager.default.fileExists(atPath: $0.path) }.map { $0 as NSURL }
    }

    /// The line stays in the note as it was; the task is a new thing in the note's Space.
    private func makeTask(_ title: String) {
        guard let task = store.add(ParsedCapture(title: title), currentSpace: note.space) else { return }
        onConfirm?("Added to \(task.space?.name ?? "Tasks")")
    }

    func flush() {
        store.setBody(note, markdown)
        store.save()
    }

    // MARK: Editing

    func textDidChange(_ notification: Notification) {
        restyle()
        store.setBody(note, markdown)
    }

    /// Links open in the preferred browser, like links everywhere else in the panel.
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
        guard let url, let onOpenLink else { return false }
        onOpenLink(url)
        return true
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
        guard !applying, let text else { return true }
        if text == "\n" { return !continueList(at: range) }
        if text == " ", range.length == 0 { return !applyShortcut(at: range.location) }
        // Pasted Markdown keeps its bullets and checkboxes.
        if text.count > 1 {
            let (converted, attachments) = NoteText.editorContent(fromMarkdown: text)
            if converted != text {
                replace(range, with: attributed(converted, attachments: attachments))
                return false
            }
        }
        return true
    }

    private var string: NSString { (textView.textStorage?.string ?? "") as NSString }

    private func lineRange(at location: Int) -> NSRange {
        let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
        let text = string.substring(with: paragraph)
        let trailing = text.hasSuffix("\n") ? 1 : 0
        return NSRange(location: paragraph.location, length: paragraph.length - trailing)
    }

    /// Makes an edit the same way typing does, so it can be undone with ⌘Z.
    private func replace(_ range: NSRange, with replacement: NSAttributedString, select: NSRange? = nil) {
        guard let storage = textView.textStorage else { return }
        applying = true
        if textView.shouldChangeText(in: range, replacementString: replacement.string) {
            storage.replaceCharacters(in: range, with: replacement)
            textView.didChangeText()
        }
        applying = false
        textView.setSelectedRange(select ?? NSRange(location: range.location + replacement.length, length: 0))
    }

    /// `- `, `* ` and `[] ` at the start of a line become a bullet or a checkbox.
    private func applyShortcut(at location: Int) -> Bool {
        let line = lineRange(at: location)
        let typed = string.substring(with: NSRange(location: line.location, length: location - line.location))
        guard let shortcut = NoteText.shortcut(beforeSpace: typed) else { return false }
        let start = location - shortcut.length
        replace(NSRange(location: start, length: shortcut.length), with: marker(for: shortcut.kind))
        return true
    }

    private func marker(for kind: NoteText.LineKind) -> NSAttributedString {
        if case .checkbox(let checked) = kind {
            let result = NSMutableAttributedString(attributedString: CheckboxAttachment.string(checked: checked))
            result.append(NSAttributedString(string: " "))
            return result
        }
        return NSAttributedString(string: NoteText.bullet)
    }

    /// Return carries a bullet or checkbox onto the next line; on an empty item it ends the list.
    private func continueList(at range: NSRange) -> Bool {
        let line = lineRange(at: range.location)
        let text = string.substring(with: line)
        let kind = kind(of: text, at: line.location)
        guard kind == .bullet || kind == .checkbox(checked: false) else { return false }
        let indent = NoteText.splitIndent(text).indent
        let markerStart = line.location + (indent as NSString).length
        let markerLength = 2
        let content = string.substring(with: NSRange(location: markerStart + markerLength, length: NSMaxRange(line) - markerStart - markerLength))
        if content.trimmingCharacters(in: .whitespaces).isEmpty {
            replace(NSRange(location: markerStart, length: NSMaxRange(line) - markerStart), with: NSAttributedString())
            return true
        }
        let next = NSMutableAttributedString(string: "\n" + indent)
        next.append(marker(for: kind == .bullet ? .bullet : .checkbox(checked: false)))
        replace(range, with: next)
        return true
    }

    private func toggleCheckbox(at index: Int) {
        guard let box = textView.textStorage?.attribute(.attachment, at: index, effectiveRange: nil) as? CheckboxAttachment else { return }
        let selection = textView.selectedRange()
        replace(NSRange(location: index, length: 1), with: CheckboxAttachment.string(checked: !box.isChecked), select: selection)
    }

    /// ⌘B bold, ⇧⌘L checklist line, ⇧⌘U check or uncheck, matching Apple Notes where it has them.
    /// ⌘F find, ⌘G and ⇧⌘G next and previous match, ⌘E find the selection.
    private func command(_ key: String, _ flags: NSEvent.ModifierFlags) -> Bool {
        switch (key, flags) {
        case ("f", [.command]):
            showFind()
        case ("g", [.command]):
            textView.finderAction(.nextMatch)
        case ("g", [.command, .shift]):
            textView.finderAction(.previousMatch)
        case ("e", [.command]):
            textView.finderAction(.setSearchString)
        case ("b", [.command]):
            toggleBold()
        case ("l", [.command, .shift]):
            toggleChecklistLine()
        case ("u", [.command, .shift]):
            let line = lineRange(at: textView.selectedRange().location)
            let indent = NoteText.splitIndent(string.substring(with: line)).indent
            let index = line.location + (indent as NSString).length
            guard index < string.length, textView.textStorage?.attribute(.attachment, at: index, effectiveRange: nil) is CheckboxAttachment else {
                return true
            }
            toggleCheckbox(at: index)
        default:
            return false
        }
        return true
    }

    private func toggleChecklistLine() {
        let selection = textView.selectedRange()
        let line = lineRange(at: selection.location)
        let text = string.substring(with: line)
        let indentLength = (NoteText.splitIndent(text).indent as NSString).length
        let start = line.location + indentLength
        switch kind(of: text, at: line.location) {
        case .checkbox:
            replace(NSRange(location: start, length: 2), with: NSAttributedString(), select: NSRange(location: max(start, selection.location - 2), length: 0))
        case .bullet:
            replace(NSRange(location: start, length: 2), with: marker(for: .checkbox(checked: false)), select: selection)
        default:
            replace(NSRange(location: start, length: 0), with: marker(for: .checkbox(checked: false)), select: NSRange(location: selection.location + 2, length: 0))
        }
    }

    private func toggleBold() {
        let selection = textView.selectedRange()
        let before = NSRange(location: selection.location - 2, length: 2)
        let after = NSRange(location: NSMaxRange(selection), length: 2)
        if before.location >= 0, NSMaxRange(after) <= string.length,
           string.substring(with: before) == "**", string.substring(with: after) == "**" {
            let inner = string.substring(with: selection)
            replace(NSRange(location: before.location, length: NSMaxRange(after) - before.location), with: NSAttributedString(string: inner),
                    select: NSRange(location: before.location, length: selection.length))
            return
        }
        let inner = string.substring(with: selection)
        replace(selection, with: NSAttributedString(string: "**\(inner)**"), select: NSRange(location: selection.location + 2, length: selection.length))
    }

    // MARK: Styling

    private static let boldPattern = try! NSRegularExpression(pattern: #"\*\*(?=\S)(.+?)(?<=\S)\*\*"#)
    private static let linkPattern = try! NSRegularExpression(pattern: #"\[([^\]\n]+)\]\((https?://[^)\s]+)\)"#)
    private static let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// Restyles the whole note. Notes are short, so this stays well under a frame.
    func restyle() {
        guard let storage = textView.textStorage else { return }
        let text = storage.string as NSString
        let full = NSRange(location: 0, length: text.length)
        let body = NoteStyle.body
        let base: [NSAttributedString.Key: Any] = [.font: body, .foregroundColor: NSColor.labelColor, .paragraphStyle: NoteStyle.paragraph()]
        let quiet = NSColor.tertiaryLabelColor
        let markerWidth = (NoteText.bullet as NSString).size(withAttributes: [.font: body]).width

        storage.beginEditing()
        storage.removeAttribute(.link, range: full)
        storage.removeAttribute(.strikethroughStyle, range: full)
        storage.addAttributes(base, range: full)

        var isFirstLine = true
        text.enumerateSubstrings(in: full, options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
            let line = text.substring(with: range)
            // Pictures don't make a title; the first line of words does.
            let words = line.replacingOccurrences(of: String(NoteText.checkboxCharacter), with: "").trimmingCharacters(in: .whitespaces)
            let lineKind = self.kind(of: line, at: range.location)
            defer { if !words.isEmpty || lineKind != .plain { isFirstLine = false } }
            let indent = (NoteText.splitIndent(line).indent as NSString).length
            switch lineKind {
            case .heading(let level):
                storage.addAttribute(.font, value: NoteStyle.heading(level), range: range)
                storage.addAttribute(.foregroundColor, value: quiet, range: NSRange(location: range.location + indent, length: level))
            case .bullet:
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: NSRange(location: range.location + indent, length: 1))
                storage.addAttribute(.paragraphStyle, value: NoteStyle.paragraph(headIndent: markerWidth), range: range)
            case .checkbox:
                storage.addAttribute(.paragraphStyle, value: NoteStyle.paragraph(headIndent: markerWidth + 4), range: range)
                let box = storage.attribute(.attachment, at: range.location + indent, effectiveRange: nil) as? CheckboxAttachment
                if box?.isChecked == true, range.length > indent + 2 {
                    let rest = NSRange(location: range.location + indent + 2, length: range.length - indent - 2)
                    storage.addAttributes([.foregroundColor: NSColor.secondaryLabelColor,
                                           .strikethroughStyle: NSUnderlineStyle.single.rawValue], range: rest)
                }
            case .plain:
                if isFirstLine { storage.addAttribute(.font, value: NoteStyle.title, range: range) }
            }
        }

        for match in Self.boldPattern.matches(in: storage.string, range: full) {
            let inner = match.range(at: 1)
            storage.enumerateAttribute(.font, in: inner) { value, range, _ in
                let font = value as? NSFont ?? body
                storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask), range: range)
            }
            storage.addAttribute(.foregroundColor, value: quiet, range: NSRange(location: match.range.location, length: 2))
            storage.addAttribute(.foregroundColor, value: quiet, range: NSRange(location: NSMaxRange(match.range) - 2, length: 2))
        }

        var linked: [NSRange] = []
        for match in Self.linkPattern.matches(in: storage.string, range: full) {
            let label = match.range(at: 1)
            guard let url = URL(string: text.substring(with: match.range(at: 2))) else { continue }
            storage.addAttribute(.foregroundColor, value: quiet, range: match.range)
            storage.addAttribute(.link, value: url, range: label)
            linked.append(match.range)
        }
        for match in Self.detector.matches(in: storage.string, range: full) {
            guard let url = match.url, !linked.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else { continue }
            storage.addAttribute(.link, value: url, range: match.range)
        }
        storage.endEditing()
        textView.typingAttributes = base
    }
}
