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
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )

                if shouldShowHelp {
                    Text("Shortcuts: ⌘B bold, ⌘I italic, ⌘⇧C copy. Use markdown markers like **bold**, *italic*, and - lists.")
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
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var header: some View {
        HStack {
            Text("Notes")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)

            Spacer()

            Button(action: openFloatingWindow) {
                HStack(spacing: 4) {
                    Text("Open Outside")
                    Text("↗")
                }
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            }
            .buttonStyle(.plain)
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
        textView.maxSize = NSSize(width: .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView

        context.coordinator.textView = textView
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesRuler = false
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor.labelColor
        textView.textContainerInset = NSSize(width: 6, height: 10)
        textView.textContainer?.lineFragmentPadding = 6
        textView.insertionPointColor = NSColor.controlAccentColor
        textView.smartInsertDeleteEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
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

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        if textView.string != text {
            context.coordinator.isProgrammaticChange = true
            textView.string = text
            context.coordinator.isProgrammaticChange = false
        }

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
        } else if flags == [.command, .shift] && characters == "c" {
            copyShortcutHandler?()
            return
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
        scrollRangeToVisible(selectedRange)
        onTextWrapped?()
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
