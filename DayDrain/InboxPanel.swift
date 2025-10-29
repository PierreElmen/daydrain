import SwiftUI
import AppKit

struct InboxPanel: View {
    @ObservedObject var manager: ToDoManager
    var onClose: () -> Void

    @FocusState private var focusedIndex: Int?

    private var tasks: [InboxTask] { manager.inboxTasks }

    var body: some View {
        VStack {
            Spacer()

            VStack(alignment: .leading, spacing: 14) {
                header

                if !manager.isInboxCollapsed {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if tasks.isEmpty {
                                Text("Inbox is clear.")
                                    .font(.system(size: 12, weight: .regular, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            } else {
                                ForEach(Array(tasks.enumerated()), id: \.offset) { index, task in
                                    InboxRow(
                                        task: task,
                                        onToggle: { manager.toggleInboxTaskDone(at: index) },
                                        onTextChange: { manager.updateInboxTaskText(at: index, text: $0) },
                                        onPriorityChange: { manager.setInboxPriority(at: index, priority: $0) },
                                        onPromote: { _ = manager.moveInboxTaskToFocus(at: index) },
                                        onDemote: { _ = manager.moveInboxTaskToOverflow(at: index) },
                                        onDelete: { manager.removeInboxTask(at: index) }
                                    )
                                    .focused($focusedIndex, equals: index)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 260)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Button(action: addTask) {
                    Label("New Inbox Item", systemImage: "plus.circle")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .labelStyle(.titleAndIcon)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 20)
            .frame(width: 320)
            .background(BlurredPanel())
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.28), radius: 20, x: 0, y: 14)
        }
        .padding(.bottom, 24)
        .padding(.horizontal, 16)
        .onAppear { focusedIndex = manager.focusedInboxIndex }
        .onReceive(manager.$focusedInboxIndex) { index in
            DispatchQueue.main.async {
                focusedIndex = index
            }
        }
        .onChange(of: focusedIndex) { index in
            if manager.focusedInboxIndex != index {
                manager.focusedInboxIndex = index
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: toggleCollapsed) {
                HStack(spacing: 6) {
                    Image(systemName: manager.isInboxCollapsed ? "chevron.right.circle" : "chevron.down.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Inbox (\(tasks.count))")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: addTask) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.secondary.opacity(0.75))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add inbox item")

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.secondary.opacity(0.75))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close inbox")
        }
    }

    private func toggleCollapsed() {
        withAnimation(.easeInOut(duration: 0.2)) {
            manager.toggleInboxCollapsed()
        }
    }

    private func addTask() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            manager.addInboxTask()
        }
    }
}

private struct InboxRow: View {
    var task: InboxTask
    var onToggle: () -> Void
    var onTextChange: (String) -> Void
    var onPriorityChange: (InboxPriority) -> Void
    var onPromote: () -> Void
    var onDemote: () -> Void
    var onDelete: () -> Void

    @State private var draftText: String

    init(task: InboxTask, onToggle: @escaping () -> Void, onTextChange: @escaping (String) -> Void, onPriorityChange: @escaping (InboxPriority) -> Void, onPromote: @escaping () -> Void, onDemote: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.task = task
        self.onToggle = onToggle
        self.onTextChange = onTextChange
        self.onPriorityChange = onPriorityChange
        self.onPromote = onPromote
        self.onDemote = onDemote
        self.onDelete = onDelete
        _draftText = State(initialValue: task.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button(action: onToggle) {
                    Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(task.done ? Color.green.opacity(0.8) : Color.secondary.opacity(0.75))
                }
                .buttonStyle(.plain)

                TextField("Inbox task…", text: Binding(
                    get: { draftText },
                    set: { newValue in
                        draftText = newValue
                        onTextChange(newValue)
                    }
                ), axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, weight: .regular, design: .rounded))
                .disableAutocorrection(true)
                .onChange(of: task.text) { newValue in
                    if newValue != draftText {
                        draftText = newValue
                    }
                }

                priorityMenu

                Button(action: onPromote) {
                    Image(systemName: "arrow.up.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.accentColor.opacity(0.85))
                }
                .buttonStyle(.plain)
                .help("Move to Focus")

                Button(action: onDemote) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.secondary.opacity(0.75))
                }
                .buttonStyle(.plain)
                .help("Move to Overflow")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.secondary.opacity(0.65))
                }
                .buttonStyle(.plain)
                .help("Remove inbox task")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(task.done ? 0.05 : 0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(priorityStroke, lineWidth: 1)
        )
    }

    private var priorityMenu: some View {
        Menu {
            ForEach(InboxPriority.allCases, id: \.self) { priority in
                Button(action: { onPriorityChange(priority) }) {
                    Label(priorityTitle(priority), systemImage: priorityIcon(priority))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(priorityEmoji(task.priority))
                Text(priorityShortTitle(task.priority))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.12))
            )
        }
        .menuStyle(.borderlessButton)
    }

    private func priorityEmoji(_ priority: InboxPriority) -> String {
        switch priority {
        case .must:
            return "🔥"
        case .medium:
            return "⭐️"
        case .nice:
            return "🌱"
        }
    }

    private func priorityShortTitle(_ priority: InboxPriority) -> String {
        switch priority {
        case .must:
            return "Must"
        case .medium:
            return "Soon"
        case .nice:
            return "Later"
        }
    }

    private func priorityTitle(_ priority: InboxPriority) -> String {
        switch priority {
        case .must:
            return "Must"
        case .medium:
            return "Meaningful"
        case .nice:
            return "Nice"
        }
    }

    private func priorityIcon(_ priority: InboxPriority) -> String {
        switch priority {
        case .must:
            return "flame"
        case .medium:
            return "star"
        case .nice:
            return "leaf"
        }
    }

    private var priorityStroke: Color {
        switch task.priority {
        case .must:
            return Color.orange.opacity(0.4)
        case .medium:
            return Color.blue.opacity(0.35)
        case .nice:
            return Color.green.opacity(0.35)
        }
    }
}

private struct BlurredPanel: View {
    var body: some View {
        VisualEffectPanel(material: .hudWindow, blendingMode: .withinWindow)
            .overlay(
                LinearGradient(colors: [Color.black.opacity(0.35), Color.black.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
    }
}

private struct VisualEffectPanel: NSViewRepresentable {
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
