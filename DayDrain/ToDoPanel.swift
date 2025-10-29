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

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header with navigation
                HStack(spacing: 12) {
                    Button(action: manager.goToPreviousDay) {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(NavButtonStyle())
                    .disabled(isAtFirstDay)
                    .help("Previous day")
                    
                    Text(manager.descriptor(for: manager.selectedDate))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary.opacity(0.85))
                        .frame(maxWidth: .infinity)
                    
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
                .onTapGesture {
                    focusedTaskID = nil
                }
                
                // Subtitle
                Text("Focus on the most important tasks")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        focusedTaskID = nil
                    }
                
                // Main focus content (no scroll)
                if let selectedEntry = manager.dayEntries.first(where: { Calendar.current.isDate($0.date, inSameDayAs: manager.selectedDate) }) {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(selectedEntry.snapshot.tasks) { task in
                                FocusTaskRow(
                                    task: task,
                                    isHighlighted: manager.highlightedTaskID == task.id,
                                    onToggle: { manager.toggleTaskCompletion(on: selectedEntry.date, taskID: task.id) },
                                    onTextChange: { manager.updateTaskText(on: selectedEntry.date, taskID: task.id, text: $0) },
                                    onNoteChange: { manager.updateNote(on: selectedEntry.date, taskID: task.id, note: $0) },
                                    onClear: { manager.clearTask(on: selectedEntry.date, taskID: task.id) }
                                )
                                .focused($focusedTaskID, equals: task.id)
                                .conditionalModifier(canDrag(task: task)) {
                                    $0.onDrag { NSItemProvider(object: manager.dragPayload(for: selectedEntry.date, taskID: task.id) as NSString) }
                                }
                            }
                        }

                        OverflowList(manager: manager)
                            .padding(.horizontal, 2)
                    }
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .onDrop(of: [UTType.utf8PlainText], delegate: DropDelegate(onDrop: { manager.handleDropPayload($0, to: selectedEntry.date) }))
                }
                
                Spacer(minLength: 16)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        focusedTaskID = nil
                    }
                
                Divider()
                    .padding(.horizontal, 12)
                
                // Compact bottom toolbar
                HStack(spacing: 8) {
                    Button(action: manager.triggerWindDownPrompt) {
                        Image(systemName: "moon.zzz.fill")
                    }
                    .buttonStyle(CompactButtonStyle())
                    .help("Wind Down")

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            manager.toggleInboxPanelVisibility()
                        }
                    }) {
                        Image(systemName: manager.isInboxPanelVisible ? "paperplane.fill" : "paperplane")
                    }
                    .buttonStyle(CompactButtonStyle())
                    .help("Toggle Inbox")

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
            .frame(width: panelWidth)
            .fixedSize(horizontal: true, vertical: true)
            .background(PanelBackground())
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 8)
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : -12)

            if manager.isInboxPanelVisible {
                InboxPanel(manager: manager, onClose: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        manager.hideInboxPanel()
                    }
                })
                .zIndex(1)
            }

            if manager.isWindDownPromptVisible {
                WindDownPrompt(
                    onSelectMood: { manager.logMood($0) },
                    onCancel: { manager.dismissWindDownPrompt() }
                )
                .transition(.scale(scale: 0.94).combined(with: .opacity))
                .zIndex(2)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: manager.isWindDownPromptVisible)
        .onAppear {
            isVisible = true
            focusedTaskID = manager.focusedTaskID
        }
        .onChange(of: focusedTaskID) { manager.focusedTaskID = $0 }
        .onReceive(manager.$focusedTaskID) { focusedTaskID = $0 }
    }
    
    private func canDrag(task: FocusTask) -> Bool {
        let trimmed = task.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !task.done
    }
}

private extension ToDoPanel {
    var isAtFirstDay: Bool {
        guard let first = manager.weekDates.first else { return true }
        return Calendar.current.isDate(manager.selectedDate, inSameDayAs: first)
    }

    var isAtLastDay: Bool {
        guard let last = manager.weekDates.last else { return true }
        return Calendar.current.isDate(manager.selectedDate, inSameDayAs: last)
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

    @State private var isNoteVisible: Bool

    init(task: FocusTask, isHighlighted: Bool, onToggle: @escaping () -> Void, onTextChange: @escaping (String) -> Void, onNoteChange: @escaping (String) -> Void, onClear: @escaping () -> Void) {
        self.task = task
        self.isHighlighted = isHighlighted
        self.onToggle = onToggle
        self.onTextChange = onTextChange
        self.onNoteChange = onNoteChange
        self.onClear = onClear
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

                    TextField("Add focus…", text: Binding(
                        get: { task.text },
                        set: { onTextChange($0) }
                    ), axis: .vertical)
                        .lineLimit(1...2)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .disableAutocorrection(true)
                        .padding(.vertical, 6)

                    Button(action: { withAnimation { isNoteVisible.toggle() } }) {
                        Image(systemName: "note.text")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(noteTint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Toggle note")

                    if !task.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button(action: onClear) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(Color.secondary.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .opacity(0.85)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(task.done ? 0.08 : 0.12))
                )

                if isNoteVisible {
                    TextField("Add note…", text: Binding(
                        get: { task.note },
                        set: { onNoteChange(String($0.prefix(200))) }
                    ), axis: .vertical)
                        .lineLimit(1...2)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5, weight: .regular, design: .rounded))
                        .disableAutocorrection(true)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(highlightBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.orange.opacity(isHighlighted ? 0.45 : 0.0), lineWidth: 1)
                .shadow(color: Color.orange.opacity(isHighlighted ? 0.25 : 0), radius: isHighlighted ? 6 : 0)
        )
        .animation(.easeInOut(duration: 0.25), value: task.done)
        .animation(.easeInOut(duration: 0.25), value: isHighlighted)
        .onChange(of: task.note) { note in
            if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                isNoteVisible = true
            }
        }
    }

    private var noteTint: Color {
        if !task.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Color.blue.opacity(0.75)
        }
        return Color.secondary.opacity(0.65)
    }

    private var highlightBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(
                LinearGradient(
                    colors: isHighlighted
                        ? [Color.orange.opacity(0.18), Color.orange.opacity(0.05)]
                        : [Color.primary.opacity(0.04), Color.primary.opacity(0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .animation(.easeInOut(duration: 0.3), value: isHighlighted)
    }
}

private struct WindDownPrompt: View {
    var onSelectMood: (Int) -> Void
    var onCancel: () -> Void

    private let moods: [(Int, String)] = [
        (1, "😫"),
        (2, "😕"),
        (3, "😐"),
        (4, "🙂"),
        (5, "😄")
    ]

    var body: some View {
        VStack(spacing: 18) {
            Text("How did your day feel today?")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.primary.opacity(0.9))

            HStack(spacing: 10) {
                ForEach(moods, id: \.0) { mood in
                    Button(action: { onSelectMood(mood.0) }) {
                        Text(mood.1)
                            .font(.system(size: 20))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.15))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                }
            }

            Button("Maybe later", action: onCancel)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.secondary.opacity(0.8))
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.black.opacity(0.4))
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 30, x: 0, y: 10)
    }
}

private struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = blendingMode
        view.material = material
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

private extension View {
    @ViewBuilder
    func conditionalModifier<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
