import SwiftUI

struct OverflowList: View {
    @ObservedObject var manager: ToDoManager
    @FocusState private var focusedIndex: Int?

    private var tasks: [OverflowTask] { manager.overflowTasks }
    private var isCollapsed: Bool { manager.isOverflowCollapsed }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if !isCollapsed {
                VStack(alignment: .leading, spacing: 8) {
                    if tasks.isEmpty {
                        Text("Nothing extra waiting.")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(Array(tasks.enumerated()), id: \.offset) { index, task in
                            OverflowRow(
                                task: task,
                                onToggle: { manager.toggleOverflowTaskDone(at: index) },
                                onTextChange: { manager.updateOverflowTaskText(at: index, text: $0) },
                                onPromote: { _ = manager.promoteOverflowTaskToFocus(at: index) },
                                onMoveToInbox: { _ = manager.moveOverflowTaskToInbox(at: index) },
                                onDelete: { manager.removeOverflowTask(at: index) }
                            )
                            .opacity(task.done ? 0.55 : 1)
                            .focused($focusedIndex, equals: index)
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { focusedIndex = manager.focusedOverflowIndex }
        .onReceive(manager.$focusedOverflowIndex) { index in
            DispatchQueue.main.async {
                focusedIndex = index
            }
        }
        .onChange(of: focusedIndex) { index in
            if manager.focusedOverflowIndex != index {
                manager.focusedOverflowIndex = index
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isCollapsed)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: toggleCollapsed) {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right.circle" : "chevron.down.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Overflow (\(tasks.count))")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: addTask) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.secondary.opacity(0.75))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add overflow task")
        }
        .padding(.horizontal, 4)
    }

    private func toggleCollapsed() {
        withAnimation(.easeInOut(duration: 0.2)) {
            manager.toggleOverflowCollapsed()
        }
    }

    private func addTask() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            manager.addOverflowTask()
        }
    }
}

private struct OverflowRow: View {
    var task: OverflowTask
    var onToggle: () -> Void
    var onTextChange: (String) -> Void
    var onPromote: () -> Void
    var onMoveToInbox: () -> Void
    var onDelete: () -> Void

    @State private var draftText: String

    init(task: OverflowTask, onToggle: @escaping () -> Void, onTextChange: @escaping (String) -> Void, onPromote: @escaping () -> Void, onMoveToInbox: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.task = task
        self.onToggle = onToggle
        self.onTextChange = onTextChange
        self.onPromote = onPromote
        self.onMoveToInbox = onMoveToInbox
        self.onDelete = onDelete
        _draftText = State(initialValue: task.text)
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(task.done ? Color.green.opacity(0.8) : Color.secondary.opacity(0.75))
            }
            .buttonStyle(.plain)

            TextField("Overflow task…", text: Binding(
                get: { draftText },
                set: { newValue in
                    draftText = newValue
                    onTextChange(newValue)
                }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 12.5, weight: .regular, design: .rounded))
            .disableAutocorrection(true)
            .onChange(of: task.text) { newValue in
                if newValue != draftText {
                    draftText = newValue
                }
            }

            Spacer(minLength: 6)

            Button(action: onPromote) {
                Image(systemName: "arrow.up.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.accentColor.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("Move to Focus")

            Button(action: onMoveToInbox) {
                Image(systemName: "paperplane")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.secondary.opacity(0.75))
            }
            .buttonStyle(.plain)
            .help("Send to Inbox")

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.secondary.opacity(0.55))
            }
            .buttonStyle(.plain)
            .help("Remove overflow task")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(task.done ? 0.06 : 0.1))
        )
    }
}

