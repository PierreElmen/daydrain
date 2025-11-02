import SwiftUI
import AppKit

final class FloatingNoteViewModel: ObservableObject {
    @Published var isPinned: Bool

    init(isPinned: Bool) {
        self.isPinned = isPinned
    }
}

struct FloatingNoteView: View {
    @ObservedObject var manager: ToDoManager
    @ObservedObject var viewModel: FloatingNoteViewModel

    @State private var draft: String
    @State private var isEditorFocused: Bool
    @State private var isHovering: Bool = false
    @State private var isHeaderHovering: Bool = false

    init(manager: ToDoManager, viewModel: FloatingNoteViewModel) {
        self.manager = manager
        self.viewModel = viewModel
        _draft = State(initialValue: manager.currentNote.content)
        _isEditorFocused = State(initialValue: true)
    }

    private var shouldShowHelp: Bool {
        draft
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains("/help")
    }

    private var headerOpacity: Double {
        (isHovering || isHeaderHovering) ? 1 : 0
    }

    private var headerTitle: String {
        Self.headerFormatter.string(from: manager.selectedNoteDate)
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 12) {
                DailyNoteEditor(
                    manager: manager,
                    text: $draft,
                    isFirstResponder: $isEditorFocused,
                    onTextChange: manager.updateNoteContent,
                    onFocusLoss: manager.persistCurrentNote,
                    onCopyShortcut: manager.copyNoteToClipboard
                )
                .frame(minHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if shouldShowHelp {
                    Text("Shortcuts: ⌘B bold, ⌘I italic, ⌘⇧C copy. Markdown markers keep things lightweight.")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 64)
            .padding(.bottom, 24)

            header
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .opacity(headerOpacity)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onAppear {
            draft = manager.currentNote.content
            isEditorFocused = true
        }
        .onReceive(manager.$currentNote) { note in
            if note.content != draft {
                draft = note.content
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.25)) {
                isHovering = hovering
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: manager.jumpToPreviousDay) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 24, height: 24)
            .background(Capsule().fill(Color.primary.opacity(0.08)))

            Text(headerTitle)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.primary.opacity(0.85))
                .frame(maxWidth: .infinity)

            Button(action: manager.jumpToNextDay) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 24, height: 24)
            .background(Capsule().fill(Color.primary.opacity(0.08)))

            Button(action: togglePin) {
                Text(viewModel.isPinned ? "📌" : "📍")
                    .font(.system(size: 14))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.88))
                .blur(radius: 0.6)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 10)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHeaderHovering = hovering
            }
        }
    }

    private func togglePin() {
        let newValue = !viewModel.isPinned
        viewModel.isPinned = newValue
    }

    private static let headerFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE · MMM d"
        formatter.locale = Locale.autoupdatingCurrent
        return formatter
    }()
}
