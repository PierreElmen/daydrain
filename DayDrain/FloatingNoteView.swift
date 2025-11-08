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
    var onClose: () -> Void

    @State private var draft: String
    @State private var isEditorFocused: Bool
    @State private var isHeaderHovering: Bool = false
    @State private var isTopHovering: Bool = false

    init(manager: ToDoManager, viewModel: FloatingNoteViewModel, onClose: @escaping () -> Void) {
        self.manager = manager
        self.viewModel = viewModel
        self.onClose = onClose
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
        (isTopHovering || isHeaderHovering) ? 1 : 0
    }

    private var headerTitle: String {
        Self.headerFormatter.string(from: manager.selectedNoteDate)
    }

    var body: some View {
        ZStack(alignment: .top) {
            VisualEffectBlurView(material: .hudWindow, blendingMode: .withinWindow)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

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

                if shouldShowHelp {
                    Text("Shortcuts: ⌘B bold, ⌘I italic, ⌘⇧X strike, ⌘⇧8 bullet, ⌘⇧C copy. Markdown markers keep things lightweight: **bold**, *italic*, ~~strike~~, * bullets.")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 24)

            HoverCaptureView { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isTopHovering = hovering
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .padding(.horizontal, 16)
            .padding(.top, 12)

            header
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .opacity(headerOpacity)
                .allowsHitTesting(headerOpacity > 0)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
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
    }

    private var header: some View {
        HStack(spacing: 10) {
            headerButton(icon: "xmark", tint: Color.primary.opacity(0.75), backgroundOpacity: 0.16) {
                onClose()
            }
            .accessibilityLabel("Close notes window")

            headerButton(icon: "chevron.left") {
                manager.jumpToPreviousDay()
            }
            .accessibilityLabel("Previous day")

            Text(headerTitle)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.primary.opacity(0.88))
                .frame(maxWidth: .infinity)

            headerButton(icon: "chevron.right") {
                manager.jumpToNextDay()
            }
            .accessibilityLabel("Next day")

            headerButton(
                icon: viewModel.isPinned ? "pin.fill" : "pin",
                tint: viewModel.isPinned ? Color.accentColor : Color.primary.opacity(0.85),
                backgroundOpacity: viewModel.isPinned ? 0.18 : 0.12
            ) {
                togglePin()
            }
            .accessibilityLabel(viewModel.isPinned ? "Unpin window" : "Pin window")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            VisualEffectBlurView(material: .menu, blendingMode: .withinWindow)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.14))
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.16), radius: 18, x: 0, y: 12)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHeaderHovering = hovering
            }
        }
    }

    private func headerButton(icon: String, tint: Color = Color.primary.opacity(0.85), backgroundOpacity: Double = 0.12, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(backgroundOpacity))
                )
        }
        .buttonStyle(.plain)
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

private struct VisualEffectBlurView: NSViewRepresentable {
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

private struct HoverCaptureView: NSViewRepresentable {
    var onHover: (Bool) -> Void

    init(onHover: @escaping (Bool) -> Void) {
        self.onHover = onHover
    }

    func makeNSView(context: Context) -> HoverCaptureNSView {
        let view = HoverCaptureNSView()
        view.onHover = onHover
        return view
    }

    func updateNSView(_ nsView: HoverCaptureNSView, context: Context) {
        nsView.onHover = onHover
    }
}

private final class HoverCaptureNSView: NSView {
    var onHover: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        translatesAutoresizingMaskIntoConstraints = false
    }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .activeAlways,
            .inVisibleRect
        ]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover?(false)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
