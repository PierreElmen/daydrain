import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ToDoPanel: View {
    @ObservedObject var manager: ToDoManager
    var openSettings: () -> Void
    var quitApplication: () -> Void

    @State private var isVisible = false
    @FocusState private var focusedTaskID: FocusTask.ID?

    private let panelWidth: CGFloat = 320

    private var selectedDateBinding: Binding<Date> {
        Binding(
            get: { manager.selectedDate },
            set: { manager.select(date: $0) }
        )
    }

    private var currentEntry: ToDoManager.DayEntry? {
        manager.dayEntries.first { Calendar.current.isDate($0.date, inSameDayAs: manager.selectedDate) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                header
                subtitle
                content
                Divider()
                    .padding(.horizontal, 12)
                bottomBar
            }
            .frame(width: panelWidth)
            .background(PanelBackground())
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 8)
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : -12)
            .overlay(inboxOverlay, alignment: .top)

            if manager.isWindDownPromptVisible {
                WindDownPrompt(
                    onSelectMood: { manager.logMood($0) },
                    onCancel: { manager.dismissWindDownPrompt() }
                )
                .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .confirmationDialog(
            "Replace one of today’s focuses?",
            isPresented: Binding(
                get: { manager.pendingInboxPromotion != nil },
                set: { if !$0 { manager.cancelPromotionRequest() } }
            ),
            presenting: manager.pendingInboxPromotion
        ) { item in
            if let entry = currentEntry {
                ForEach(entry.snapshot.tasks) { task in
                    Button("\(task.label): \(focusPreview(task))") {
                        _ = manager.replaceFocus(with: task.label, using: item.id)
                    }
                }
            }
            Button("Cancel", role: .cancel) { manager.cancelPromotionRequest() }
        } message: { _ in
            Text("Choose the focus slot to replace with \(manager.pendingInboxPromotion?.text ?? "this item").")
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: manager.isWindDownPromptVisible)
        .animation(.easeInOut(duration: 0.22), value: manager.isInboxExpanded)
        .animation(.easeInOut(duration: 0.18), value: manager.isOverflowCollapsed)
        .onAppear {
            isVisible = true
            focusedTaskID = manager.focusedTaskID
        }
        .onReceive(manager.$focusedTaskID) { focusedTaskID = $0 }
        .onChange(of: focusedTaskID) { id in
            if let id {
                manager.setActiveContext(.focus(id))
            } else {
                manager.setActiveContext(nil)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: manager.goToPreviousDay) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(NavButtonStyle())
            .disabled(isAtFirstDay)
            .help("Previous day")

            DatePicker(
                "",
                selection: selectedDateBinding,
                displayedComponents: [.date]
            )
            .labelsHidden()
            .datePickerStyle(.field)
            .frame(maxWidth: .infinity)
            .overlay(
                Text(manager.descriptor(for: manager.selectedDate))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary.opacity(0.85))
                    .allowsHitTesting(false)
            )
            .onTapGesture {
                focusedTaskID = nil
            }

            Button(action: manager.goToNextDay) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(NavButtonStyle())
            .disabled(isAtLastDay)
            .help("Next day")
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .contentShape(Rectangle())
        .onTapGesture { focusedTaskID = nil }
    }

    private var subtitle: some View {
        Text("Focus on the most important tasks")
            .font(.system(size: 11, weight: .regular, design: .rounded))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
            .contentShape(Rectangle())
            .onTapGesture { focusedTaskID = nil }
    }

    @ViewBuilder
    private var content: some View {
        if let entry = currentEntry {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    focusSection(for: entry)
                    OverflowSection(manager: manager, date: entry.date)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 20)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            Spacer()
        }
    }

    private func focusSection(for entry: ToDoManager.DayEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(entry.snapshot.tasks) { task in
                FocusTaskRow(
                    task: task,
                    isHighlighted: manager.highlightedTaskID == task.id,
                    onToggle: { manager.toggleTaskCompletion(on: entry.date, taskID: task.id) },
                    onTextChange: { manager.updateTaskText(on: entry.date, taskID: task.id, text: $0) },
                    onNoteChange: { manager.updateNote(on: entry.date, taskID: task.id, note: $0) },
                    onClear: { manager.clearTask(on: entry.date, taskID: task.id) },
                    onMoveToOverflow: { manager.moveFocusTaskToOverflow(task.id) },
                    onMoveToInbox: { manager.moveFocusTaskToInbox(task.id, priority: .medium) },
                    onBeginEditing: { manager.setActiveContext(.focus(task.id)) }
                )
                .focused($focusedTaskID, equals: task.id)
                .conditionalModifier(canDrag(task: task)) {
                    $0.onDrag {
                        NSItemProvider(object: manager.dragPayload(for: .focus, date: entry.date, id: task.id) as NSString)
                    }
                }
            }
        }
        .onDrop(of: [UTType.utf8PlainText], delegate: DropDelegate { payload in
            manager.handleDropPayload(payload, to: .focus, on: entry.date)
        })
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.22)) {
                    manager.toggleInboxPanel()
                }
            }) {
                Image(systemName: manager.isInboxExpanded ? "paperplane.fill" : "paperplane")
            }
            .buttonStyle(CompactButtonStyle())
            .help("Inbox")

            Button(action: manager.triggerWindDownPrompt) {
                Image(systemName: "moon.zzz.fill")
            }
            .buttonStyle(CompactButtonStyle())
            .help("Wind Down")

            Button(action: openSettings) {
                Image(systemName: "gear")
            }
            .buttonStyle(CompactButtonStyle())
            .help("Settings")

            Button(action: quitApplication) {
                Image(systemName: "power")
            }
            .buttonStyle(CompactButtonStyle())
            .help("Quit")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var inboxOverlay: some View {
        if manager.isInboxExpanded, let entry = currentEntry {
            InboxPanel(manager: manager, date: entry.date, focusTasks: entry.snapshot.tasks)
                .frame(width: panelWidth - 28)
                .padding(.top, 68)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(2)
        }
    }

    private var isAtFirstDay: Bool {
        guard let first = manager.weekDates.first else { return true }
        return Calendar.current.isDate(manager.selectedDate, inSameDayAs: first)
    }

    private var isAtLastDay: Bool {
        guard let last = manager.weekDates.last else { return true }
        return Calendar.current.isDate(manager.selectedDate, inSameDayAs: last)
    }

    private func canDrag(task: FocusTask) -> Bool {
        let trimmed = task.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !task.done
    }

    private func focusPreview(_ task: FocusTask) -> String {
        let trimmed = task.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "(empty)" }
        if trimmed.count <= 22 { return trimmed }
        return String(trimmed.prefix(22)) + "…"
    }
}

private struct NavButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundColor(Color.primary.opacity(configuration.isPressed ? 0.4 : 0.65))
            .frame(width: 28, height: 28)
            .background(
                Circle()
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.08))
            )
    }
}

private struct CompactButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.primary.opacity(configuration.isPressed ? 0.5 : 0.75))
            .frame(width: 32, height: 32)
            .background(
                Circle()
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.08))
            )
    }
}

private struct DropDelegate: SwiftUI.DropDelegate {
    let onDrop: (String) -> Void

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [UTType.utf8PlainText]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let payload = object as? String else { return }
            DispatchQueue.main.async {
                onDrop(payload)
            }
        }
        return true
    }
}

private struct PanelBackground: View {
    var body: some View {
        VisualEffectBlur(material: .menu, blendingMode: .withinWindow)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct FocusTaskRow: View {
    let task: FocusTask
    let isHighlighted: Bool
    let onToggle: () -> Void
    let onTextChange: (String) -> Void
    let onNoteChange: (String) -> Void
    let onClear: () -> Void
    let onMoveToOverflow: () -> Void
    let onMoveToInbox: () -> Void
    let onBeginEditing: () -> Void

    @State private var isNoteVisible: Bool

    init(task: FocusTask, isHighlighted: Bool, onToggle: @escaping () -> Void, onTextChange: @escaping (String) -> Void, onNoteChange: @escaping (String) -> Void, onClear: @escaping () -> Void, onMoveToOverflow: @escaping () -> Void, onMoveToInbox: @escaping () -> Void, onBeginEditing: @escaping () -> Void) {
        self.task = task
        self.isHighlighted = isHighlighted
        self.onToggle = onToggle
        self.onTextChange = onTextChange
        self.onNoteChange = onNoteChange
        self.onClear = onClear
        self.onMoveToOverflow = onMoveToOverflow
        self.onMoveToInbox = onMoveToInbox
        self.onBeginEditing = onBeginEditing
        _isNoteVisible = State(initialValue: !task.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(task.label.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(isHighlighted ? Color.orange.opacity(0.9) : Color.secondary)
                if isHighlighted {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.orange)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                Spacer()
                if task.done {
                    Text("Complete")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(Color.green.opacity(0.75))
                        .transition(.opacity)
                }
            }

            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Button(action: onToggle) {
                        Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(task.done ? Color.green : Color.secondary.opacity(0.8))
                            .font(.system(size: 16, weight: .medium))
                    }
                    .buttonStyle(.plain)

                    TextField(
                        "Add focus…",
                        text: Binding(
                            get: { task.text },
                            set: { onTextChange($0) }
                        ),
                        onEditingChanged: { editing in
                            if editing { onBeginEditing() }
                        }
                    )
                    .textFieldStyle(PlainTextFieldStyle())
                    .foregroundColor(.primary)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .disableAutocorrection(true)
                    .onSubmit { if task.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { onClear() } }

                    if !task.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button(action: { withAnimation { isNoteVisible.toggle() } }) {
                            Image(systemName: isNoteVisible ? "note.text" : "note.text.badge.plus")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color.secondary.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if isNoteVisible {
                    TextField(
                        "Add note…",
                        text: Binding(
                            get: { task.note },
                            set: { onNoteChange($0) }
                        ),
                        onEditingChanged: { editing in
                            if editing { onBeginEditing() }
                        }
                    )
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
        }
        .contextMenu {
            Button("Move to Overflow", action: onMoveToOverflow)
            Button("Send to Inbox", action: onMoveToInbox)
            if !task.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("Clear", role: .destructive, action: onClear)
            }
        }
    }
}

private struct OverflowSection: View {
    @ObservedObject var manager: ToDoManager
    let date: Date

    @State private var draft = ""
    @State private var isAdding = false
    @FocusState private var isInputFocused: Bool

    private var tasks: [OverflowTask] { manager.overflowTasks }

    private var allComplete: Bool {
        !tasks.isEmpty && tasks.allSatisfy { $0.done }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        manager.toggleOverflowSection()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: manager.isOverflowCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 11, weight: .medium))
                        Text("➕ Overflow (\(tasks.count))")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.primary.opacity(0.6))

                Spacer()

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if manager.isOverflowCollapsed {
                            manager.toggleOverflowSection()
                        }
                        isAdding = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        isInputFocused = true
                    }
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(.primary.opacity(0.6))
                .help("Add to Overflow")
            }

            if !manager.isOverflowCollapsed {
                VStack(alignment: .leading, spacing: 8) {
                    if tasks.isEmpty && !isAdding {
                        Text("Light load · nothing in overflow")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 6)
                    }

                    ForEach(tasks) { task in
                        OverflowTaskRow(
                            task: task,
                            onToggle: { manager.toggleOverflowTask(id: task.id) },
                            onTextChange: { manager.updateOverflowTask(id: task.id, text: $0) },
                            onRemove: { manager.removeOverflowTask(id: task.id) },
                            onBeginEditing: { manager.setActiveContext(.overflow(task.id)) }
                        )
                        .onDrag {
                            NSItemProvider(object: manager.dragPayload(for: .overflow, date: date, id: task.id.uuidString) as NSString)
                        }
                    }

                    if isAdding {
                        TextField("Overflow task…", text: $draft, onEditingChanged: { editing in
                            if editing {
                                manager.setActiveContext(nil)
                            }
                        })
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                        .focused($isInputFocused)
                        .onSubmit(addTask)
                    } else if tasks.isEmpty {
                        Button("Add to Overflow", action: startAdding)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.primary.opacity(0.65))
                            .buttonStyle(.plain)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, 4)
        .opacity(allComplete ? 0.35 : 1)
        .onDrop(of: [UTType.utf8PlainText], delegate: DropDelegate { payload in
            manager.handleDropPayload(payload, to: .overflow, on: date)
        })
        .onChange(of: manager.isOverflowCollapsed) { collapsed in
            if collapsed {
                isAdding = false
            }
        }
    }

    private func startAdding() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if manager.isOverflowCollapsed {
                manager.toggleOverflowSection()
            }
            isAdding = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isInputFocused = true
        }
    }

    private func addTask() {
        guard manager.addOverflowTask(text: draft) else { return }
        draft = ""
        isAdding = false
    }
}

private struct OverflowTaskRow: View {
    let task: OverflowTask
    let onToggle: () -> Void
    let onTextChange: (String) -> Void
    let onRemove: () -> Void
    let onBeginEditing: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(task.done ? Color.green : Color.secondary.opacity(0.7))
            }
            .buttonStyle(.plain)

            TextField(
                "Overflow task…",
                text: Binding(
                    get: { task.text },
                    set: { onTextChange($0) }
                ),
                onEditingChanged: { editing in
                    if editing { onBeginEditing() }
                }
            )
            .textFieldStyle(PlainTextFieldStyle())
            .font(.system(size: 12, weight: .regular, design: .rounded))
            .foregroundColor(.primary.opacity(task.done ? 0.55 : 0.8))

            Spacer(minLength: 4)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .opacity(task.done ? 0.45 : 1)
    }
}

private struct InboxPanel: View {
    @ObservedObject var manager: ToDoManager
    let date: Date
    let focusTasks: [FocusTask]

    @State private var draft = ""
    @State private var priority: InboxPriority = .medium
    @FocusState private var isInputFocused: Bool

    private var items: [InboxItem] { manager.inboxItems }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Inbox", systemImage: "paperplane.fill")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary.opacity(0.8))
                Spacer()
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        manager.hideInboxPanel()
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Close Inbox")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Capture future focuses or nice-to-do tasks. Keep it light.")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    TextField("New inbox item…", text: $draft)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .focused($isInputFocused)
                        .onSubmit(commit)

                    Menu {
                        ForEach(InboxPriority.allCases) { option in
                            Button(option.label) { priority = option }
                        }
                    } label: {
                        InboxPriorityBadge(priority: priority)
                    }
                    .menuStyle(BorderlessButtonMenuStyle())

                    Button(action: commit) {
                        Image(systemName: "return")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.primary.opacity(0.6))
                    .help("Add to Inbox")
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView(showsIndicators: true) {
                LazyVStack(spacing: 10) {
                    if items.isEmpty {
                        Text("Inbox is calm · nothing waiting")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundColor(.secondary)
                            .padding(.top, 12)
                    }

                    ForEach(items) { item in
                        InboxItemRow(
                            item: item,
                            onToggle: { manager.toggleInboxItem(id: item.id) },
                            onTextChange: { manager.updateInboxItem(id: item.id, text: $0) },
                            onPriorityChange: { manager.updateInboxPriority(id: item.id, priority: $0) },
                            onDelete: { manager.removeInboxItem(id: item.id) },
                            onPromote: { _ = manager.attemptPromoteInboxItem(item.id) },
                            onOverflow: { manager.moveInboxToOverflow(item.id) },
                            onBeginEditing: { manager.setActiveContext(.inbox(item.id)) }
                        )
                        .onDrag {
                            NSItemProvider(object: manager.dragPayload(for: .inbox, date: date, id: item.id.uuidString) as NSString)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .frame(maxHeight: 260)
            .onDrop(of: [UTType.utf8PlainText], delegate: DropDelegate { payload in
                manager.handleDropPayload(payload, to: .inbox, on: date)
            })
        }
        .background(
            VisualEffectBlur(material: .sidebar, blendingMode: .withinWindow)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isInputFocused = true
            }
        }
    }

    private func commit() {
        guard manager.addInboxItem(text: draft, priority: priority) else { return }
        draft = ""
    }
}

private struct InboxItemRow: View {
    let item: InboxItem
    let onToggle: () -> Void
    let onTextChange: (String) -> Void
    let onPriorityChange: (InboxPriority) -> Void
    let onDelete: () -> Void
    let onPromote: () -> Void
    let onOverflow: () -> Void
    let onBeginEditing: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Button(action: onToggle) {
                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(item.done ? Color.green : Color.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 6) {
                    TextField(
                        "Capture idea…",
                        text: Binding(
                            get: { item.text },
                            set: { onTextChange($0) }
                        ),
                        onEditingChanged: { editing in
                            if editing { onBeginEditing() }
                        }
                    )
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(.primary.opacity(item.done ? 0.55 : 0.85))
                    .disableAutocorrection(true)

                    HStack(spacing: 6) {
                        Menu {
                            ForEach(InboxPriority.allCases) { option in
                                Button(option.label) { onPriorityChange(option) }
                            }
                        } label: {
                            InboxPriorityBadge(priority: item.priority)
                        }
                        .menuStyle(BorderlessButtonMenuStyle())

                        if item.done {
                            Text("Complete")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundColor(Color.green.opacity(0.7))
                        }
                    }
                }

                Spacer()

                Menu {
                    Button("Promote to Focus", action: onPromote)
                    Button("Move to Overflow", action: onOverflow)
                    Button("Delete", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .menuStyle(BorderlessButtonMenuStyle())
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.02))
        )
        .opacity(item.done ? 0.45 : 1)
    }
}

private struct InboxPriorityBadge: View {
    let priority: InboxPriority

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(priorityColor)
                .frame(width: 6, height: 6)
            Text(priority.label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.primary.opacity(0.65))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(priorityColor.opacity(0.12))
        )
    }

    private var priorityColor: Color {
        switch priority {
        case .must:
            return Color(red: 1.0, green: 0.42, blue: 0.29)
        case .medium:
            return Color(red: 0.42, green: 0.64, blue: 0.48)
        case .nice:
            return Color(red: 0.55, green: 0.65, blue: 0.79)
        }
    }
}

private extension View {
    func conditionalModifier<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            return AnyView(transform(self))
        } else {
            return AnyView(self)
        }
    }
}
