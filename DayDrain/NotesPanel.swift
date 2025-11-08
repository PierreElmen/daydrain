import SwiftUI
import Combine
import AppKit

struct NotesPanel: View {
    @ObservedObject var manager: ToDoManager
    var openFloatingWindow: () -> Void

    @State private var draft: String
    @State private var isEditorFocused: Bool

    init(manager: ToDoManager, openFloatingWindow: @escaping () -> Void) {
        self.manager = manager
        self.openFloatingWindow = openFloatingWindow
        _draft = State(initialValue: manager.currentNote.content)
        _isEditorFocused = State(initialValue: true)
    }

    private var shouldShowHelp: Bool {
        draft
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains("/help")
    }

    var body: some View {
        VStack {
            Spacer()

            VStack(alignment: .leading, spacing: 14) {
                header

                DailyNoteEditor(
                    manager: manager,
                    text: $draft,
                    isFirstResponder: $isEditorFocused,
                    onTextChange: manager.updateNoteContent,
                    onFocusLoss: manager.persistCurrentNote,
                    onCopyShortcut: manager.copyNoteToClipboard
                )
                .frame(minHeight: 200, maxHeight: 260)

                if shouldShowHelp {
                    Text("Shortcuts: ⌘B bold, ⌘I italic, ⌘⇧X strike, ⌘⇧8 bullet, ⌘⇧C copy. Use markdown markers like **bold**, *italic*, ~~strike~~, and * bullets.")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary)
                        .transition(.opacity)
                }
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 20)
            .frame(width: 320)
            .background(NotesPanelBackground())
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.28), radius: 20, x: 0, y: 14)
        }
        .padding(.bottom, 50)
        .onAppear {
            draft = manager.currentNote.content
            isEditorFocused = true
        }
        .onReceive(manager.$currentNote) { note in
            if note.content != draft {
                draft = note.content
            }
        }
        .onReceive(manager.$isNotesPanelVisible) { visible in
            guard visible else { return }
            DispatchQueue.main.async {
                isEditorFocused = true
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var header: some View {
        HStack {
            Text("Notes")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)

            Spacer()

            Button(action: openFloatingWindow) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open note in floating window")
        }
    }
}

struct DailyNoteEditor: View {
    @ObservedObject var manager: ToDoManager
    @Binding var text: String
    @Binding var isFirstResponder: Bool

    var onTextChange: (String) -> Void
    var onFocusLoss: () -> Void
    var onCopyShortcut: () -> Void

    @State private var fadeOpacity: Double
    @State private var lastNoteDate: String

    init(
        manager: ToDoManager,
        text: Binding<String>,
        isFirstResponder: Binding<Bool>,
        onTextChange: @escaping (String) -> Void,
        onFocusLoss: @escaping () -> Void,
        onCopyShortcut: @escaping () -> Void
    ) {
        self.manager = manager
        self._text = text
        self._isFirstResponder = isFirstResponder
        self.onTextChange = onTextChange
        self.onFocusLoss = onFocusLoss
        self.onCopyShortcut = onCopyShortcut
        _fadeOpacity = State(initialValue: 1)
        _lastNoteDate = State(initialValue: manager.currentNote.date)
    }

    var body: some View {
        NotesTextView(
            text: $text,
            isFirstResponder: $isFirstResponder,
            onTextChange: { newText in
                if text != newText {
                    text = newText
                }
                onTextChange(newText)
            },
            onFocusChange: { focused in
                DispatchQueue.main.async {
                    isFirstResponder = focused
                }
                if !focused {
                    onFocusLoss()
                }
            },
            onCopyShortcut: onCopyShortcut
        )
        .background(Color(NSColor.textBackgroundColor).opacity(0.02))
        .opacity(fadeOpacity)
        .onReceive(manager.$currentNote) { note in
            if note.date != lastNoteDate {
                lastNoteDate = note.date
                text = note.content
                withAnimation(.easeInOut(duration: 0.15)) {
                    fadeOpacity = 0.85
                }
                withAnimation(.easeInOut(duration: 0.25).delay(0.12)) {
                    fadeOpacity = 1
                }
            } else if note.content != text {
                text = note.content
            }
        }
    }
}

struct NotesTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFirstResponder: Bool

    var onTextChange: (String) -> Void
    var onFocusChange: (Bool) -> Void
    var onCopyShortcut: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.contentView.drawsBackground = false

        let textView = NotesTextViewImpl(frame: .zero)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView

        context.coordinator.textView = textView
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = true
        textView.importsGraphics = false
        textView.usesRuler = false
        textView.allowsUndo = true
        textView.font = textView.markdownFont
        textView.textColor = NSColor.labelColor
        textView.textContainerInset = NSSize(width: 6, height: 10)
        textView.textContainer?.lineFragmentPadding = 6
        textView.insertionPointColor = NSColor.controlAccentColor
        textView.smartInsertDeleteEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.typingAttributes = textView.markdownBaseAttributes
        textView.focusChangeHandler = { focused in
            onFocusChange(focused)
        }
        textView.copyShortcutHandler = {
            onCopyShortcut()
        }
        textView.onTextWrapped = {
            onTextChange(textView.string)
        }

        textView.string = text
        textView.refreshMarkdownHighlights()

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        if textView.string != text {
            context.coordinator.isProgrammaticChange = true
            textView.string = text
            context.coordinator.isProgrammaticChange = false
        }
        textView.refreshMarkdownHighlights()

        if isFirstResponder {
            DispatchQueue.main.async {
                if textView.window?.firstResponder !== textView {
                    textView.window?.makeFirstResponder(textView)
                }
            }
        } else if textView.window?.firstResponder === textView {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(nil)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NotesTextView
        weak var textView: NotesTextViewImpl?
        var isProgrammaticChange = false

        init(_ parent: NotesTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticChange,
                  let textView = notification.object as? NSTextView else { return }
            let updated = textView.string
            if parent.text != updated {
                parent.text = updated
            }
            parent.onTextChange(updated)
        }

    }
}

final class NotesTextViewImpl: NSTextView {
    var focusChangeHandler: ((Bool) -> Void)?
    var copyShortcutHandler: (() -> Void)?
    var onTextWrapped: (() -> Void)?

    private let markdownBaseFont = NSFont.systemFont(ofSize: 13, weight: .regular)
    private lazy var markdownBoldFont: NSFont = NSFontManager.shared.convert(markdownBaseFont, toHaveTrait: .boldFontMask)
    private lazy var markdownItalicFont: NSFont = NSFontManager.shared.convert(markdownBaseFont, toHaveTrait: .italicFontMask)
    private let inlineMarkerColor = NSColor.clear
    private let bulletMarkerColor = NSColor.secondaryLabelColor
    private var isApplyingMarkdownAttributes = false
    private var pendingHighlightWorkItem: DispatchWorkItem?
    private static let highlightDebounceInterval: TimeInterval = 0.05

    deinit {
        pendingHighlightWorkItem?.cancel()
    }

    fileprivate var markdownBaseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: markdownBaseFont,
            .foregroundColor: NSColor.labelColor
        ]
    }

    fileprivate var markdownFont: NSFont {
        markdownBaseFont
    }

    override func keyDown(with event: NSEvent) {
        guard let characters = event.charactersIgnoringModifiers?.lowercased() else {
            super.keyDown(with: event)
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == [.command] {
            switch characters {
            case "b":
                wrapSelection(with: "**")
                return
            case "i":
                wrapSelection(with: "*")
                return
            default:
                break
            }
        } else if flags == [.command, .shift] {
            switch characters {
            case "c":
                copyShortcutHandler?()
                return
            case "x":
                wrapSelection(with: "~~")
                return
            case "*", "8":
                toggleBulletList()
                return
            default:
                break
            }
        }

        super.keyDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            focusChangeHandler?(true)
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            focusChangeHandler?(false)
        }
        return result
    }

    override func didChangeText() {
        super.didChangeText()
        scheduleHighlightRefresh()
    }

    private func wrapSelection(with token: String) {
        let current = self.string as NSString
        let range = selectedRange
        let replacement: String

        if range.length > 0 {
            let selected = current.substring(with: range)
            replacement = token + selected + token
        } else {
            replacement = token + token
        }

        let updated = current.replacingCharacters(in: range, with: replacement)
        self.string = updated

        let newLocation = range.location + token.count
        let newLength = range.length > 0 ? range.length : 0
        setSelectedRange(NSRange(location: newLocation, length: newLength))
        refreshMarkdownHighlights()
        scrollRangeToVisible(selectedRange)
        onTextWrapped?()
    }

    private func toggleBulletList() {
        let nsString = self.string as NSString
        let selection = selectedRange
        let isSingleCursor = selection.length == 0
        let targetRange = nsString.lineRange(for: selection)
        let block = nsString.substring(with: targetRange)
        var lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.isEmpty {
            lines = [""]
        }

        let nsBlock = block as NSString
        var cursorLineIndex: Int?
        if isSingleCursor {
            let relativeCursor = max(0, selection.location - targetRange.location)
            let clampedCursor = min(relativeCursor, nsBlock.length)
            if clampedCursor == 0 {
                cursorLineIndex = 0
            } else {
                let prefix = nsBlock.substring(to: clampedCursor)
                let newlineCount = prefix.reduce(into: 0) { count, character in
                    if character == "\n" {
                        count += 1
                    }
                }
                cursorLineIndex = min(newlineCount, lines.count - 1)
            }
        }

        var hasBulletLine = false
        var hasNonBulletLine = false
        var firstContentIndentCount: Int?
        var firstContentHasBullet = false

        for line in lines {
            let (indentCount, trimmed) = splitIndent(in: line)
            if trimmed.isEmpty {
                continue
            }
            if firstContentIndentCount == nil {
                firstContentIndentCount = indentCount
                firstContentHasBullet = trimmed.hasPrefix("* ")
            }
            if trimmed.hasPrefix("* ") {
                hasBulletLine = true
            } else {
                hasNonBulletLine = true
            }
        }

        let shouldAddBullets: Bool
        if isSingleCursor {
            shouldAddBullets = true
        } else if !hasBulletLine && !hasNonBulletLine {
            shouldAddBullets = true
        } else {
            shouldAddBullets = hasNonBulletLine
        }

        for index in lines.indices {
            let (indentCount, trimmed) = splitIndent(in: lines[index])
            let indent = String(lines[index].prefix(indentCount))
            if trimmed.isEmpty {
                if shouldAddBullets,
                   isSingleCursor,
                   let cursorLineIndex,
                   index == cursorLineIndex {
                    lines[index] = indent + "* "
                }
                continue
            }

            if shouldAddBullets {
                if trimmed.hasPrefix("* ") {
                    continue
                }
                lines[index] = indent + "* " + trimmed
            } else {
                guard trimmed.hasPrefix("* ") else { continue }
                let newContent = String(trimmed.dropFirst(2))
                lines[index] = indent + newContent
            }
        }

        let replacement = lines.joined(separator: "\n")

        if replacement == block {
            return
        }

        self.string = nsString.replacingCharacters(in: targetRange, with: replacement)

        if isSingleCursor {
            let indentCount = firstContentIndentCount ?? 0
            if shouldAddBullets {
                let newLocation = targetRange.location + indentCount + 2
                setSelectedRange(NSRange(location: newLocation, length: 0))
            } else if firstContentHasBullet {
                let newLocation = max(selection.location - 2, targetRange.location + indentCount)
                setSelectedRange(NSRange(location: newLocation, length: 0))
            } else {
                setSelectedRange(NSRange(location: selection.location, length: 0))
            }
        } else {
            let newLength = (replacement as NSString).length
            setSelectedRange(NSRange(location: targetRange.location, length: newLength))
        }

        scrollRangeToVisible(selectedRange)
        refreshMarkdownHighlights()
        onTextWrapped?()
    }

    private func splitIndent(in line: String) -> (Int, String) {
        let indentCount = line.prefix { $0 == " " || $0 == "\t" }.count
        let trimmed = String(line.dropFirst(indentCount))
        return (indentCount, trimmed)
    }

    func refreshMarkdownHighlights() {
        pendingHighlightWorkItem?.cancel()
        guard !isApplyingMarkdownAttributes else { return }
        guard let textStorage = textStorage else { return }

        isApplyingMarkdownAttributes = true
        defer { isApplyingMarkdownAttributes = false }

        let currentSelection = selectedRange
        let fullText = textStorage.string as NSString
        let fullLength = fullText.length

        textStorage.beginEditing()
        defer { textStorage.endEditing() }

        if fullLength > 0 {
            let fullRange = NSRange(location: 0, length: fullLength)
            textStorage.setAttributes(markdownBaseAttributes, range: fullRange)
            applyBulletStyling(in: fullText)
            applyStrikethroughStyling(in: fullText)
            applyBoldStyling(in: fullText)
            applyItalicStyling(in: fullText)
        } else {
            typingAttributes = markdownBaseAttributes
            setSelectedRange(NSRange(location: 0, length: 0))
            return
        }

        typingAttributes = markdownBaseAttributes
        guard currentSelection.location != NSNotFound else { return }
        let clampedLocation = min(currentSelection.location, fullLength)
        let maxLength = max(0, fullLength - clampedLocation)
        let clampedLength = min(currentSelection.length, maxLength)
        setSelectedRange(NSRange(location: clampedLocation, length: clampedLength))
    }

    private func applyBoldStyling(in text: NSString) {
        guard let textStorage = textStorage else { return }
        guard let regex = try? NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*", options: [.dotMatchesLineSeparators]) else { return }
        let fullRange = NSRange(location: 0, length: text.length)
        regex.enumerateMatches(in: text as String, options: [], range: fullRange) { result, _, _ in
            guard let result = result, result.numberOfRanges >= 2 else { return }
            let innerRange = result.range(at: 1)
            guard innerRange.length > 0 else { return }
            textStorage.addAttribute(.font, value: markdownBoldFont, range: innerRange)
            highlightMarkers(in: result.range, markerLength: 2)
        }
    }

    private func applyItalicStyling(in text: NSString) {
        guard let textStorage = textStorage else { return }
        guard let regex = try? NSRegularExpression(
            pattern: "(?<!\\*)\\*(?![\\s\\*])(.+?)(?<![\\s\\*])\\*(?!\\*)",
            options: [.dotMatchesLineSeparators]
        ) else { return }
        let fullRange = NSRange(location: 0, length: text.length)
        regex.enumerateMatches(in: text as String, options: [], range: fullRange) { result, _, _ in
            guard let result = result, result.numberOfRanges >= 2 else { return }
            let innerRange = result.range(at: 1)
            guard innerRange.length > 0 else { return }
            textStorage.addAttribute(.font, value: markdownItalicFont, range: innerRange)
            highlightMarkers(in: result.range, markerLength: 1)
        }
    }

    private func applyStrikethroughStyling(in text: NSString) {
        guard let textStorage = textStorage else { return }
        guard let regex = try? NSRegularExpression(pattern: "~~(.+?)~~", options: [.dotMatchesLineSeparators]) else { return }
        let fullRange = NSRange(location: 0, length: text.length)
        regex.enumerateMatches(in: text as String, options: [], range: fullRange) { result, _, _ in
            guard let result = result, result.numberOfRanges >= 2 else { return }
            let innerRange = result.range(at: 1)
            guard innerRange.length > 0 else { return }
            textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: innerRange)
            highlightMarkers(in: result.range, markerLength: 2)
        }
    }

    private func applyBulletStyling(in text: NSString) {
        guard let textStorage = textStorage else { return }
        guard let regex = try? NSRegularExpression(pattern: #"(?m)^(\\s*)(\* )"#, options: []) else { return }
        let fullRange = NSRange(location: 0, length: text.length)
        regex.enumerateMatches(in: text as String, options: [], range: fullRange) { result, _, _ in
            guard let result = result, result.numberOfRanges >= 3 else { return }
            let markerRange = result.range(at: 2)
            guard markerRange.length > 0 else { return }
            textStorage.addAttribute(.foregroundColor, value: bulletMarkerColor, range: markerRange)
        }
    }

    private func highlightMarkers(in range: NSRange, markerLength: Int) {
        guard let textStorage = textStorage else { return }
        guard markerLength > 0, range.length >= markerLength * 2 else { return }

        let startRange = NSRange(location: range.location, length: markerLength)
        textStorage.addAttribute(.foregroundColor, value: inlineMarkerColor, range: startRange)

        let endLocation = range.location + range.length - markerLength
        guard endLocation >= range.location else { return }
        let endRange = NSRange(location: endLocation, length: markerLength)
        textStorage.addAttribute(.foregroundColor, value: inlineMarkerColor, range: endRange)
    }

    private func scheduleHighlightRefresh() {
        pendingHighlightWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.refreshMarkdownHighlights()
        }
        pendingHighlightWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.highlightDebounceInterval, execute: workItem)
    }
}

private struct NotesPanelBackground: View {
    var body: some View {
        NotesVisualEffectPanel(material: .hudWindow, blendingMode: .withinWindow)
            .overlay(
                LinearGradient(
                    colors: [Color.black.opacity(0.35), Color.black.opacity(0.15)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}

private struct NotesVisualEffectPanel: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.material = material
        view.blendingMode = blendingMode
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
