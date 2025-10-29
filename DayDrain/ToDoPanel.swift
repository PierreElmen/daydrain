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
            VStack(spacing: 18) {
                header
                navigation
                dayCarousel
                weeklySummary
                actionButtons
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(width: panelWidth)
            .background(PanelBackground())
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 8)
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : -12)
            .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isVisible)

            if manager.isWindDownPromptVisible {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .transition(.opacity)
                WindDownPrompt(
                    onSelectMood: { manager.logMood($0) },
                    onCancel: { manager.dismissWindDownPrompt() }
                )
                .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .onAppear {
            isVisible = true
            focusedTaskID = manager.focusedTaskID
        }
        .onReceive(manager.$focusedTaskID) { focusedTaskID = $0 }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Rhythm & Flow")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.primary.opacity(0.85))
                .padding(.top, 4)

            Text("Glance at the week, carry light notes, and end the day softly.")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var navigation: some View {
        HStack(spacing: 12) {
            Button(action: manager.goToPreviousDay) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(NavButtonStyle())
            .disabled(isAtFirstDay)

            Text(manager.descriptor(for: manager.selectedDate))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.primary.opacity(0.8))
                .frame(maxWidth: .infinity)

            Button(action: manager.goToNextDay) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(NavButtonStyle())
            .disabled(isAtLastDay)
        }
    }

    private var dayCarousel: some View {
        TabView(selection: selectedDateBinding) {
            ForEach(manager.dayEntries) { entry in
                DayCardView(
                    entry: entry,
                    highlightedTaskID: manager.highlightedTaskID,
                    descriptor: manager.descriptor(for: entry.date),
                    focusState: $focusedTaskID,
                    isSelected: Calendar.current.isDate(entry.date, inSameDayAs: manager.selectedDate),
                    payloadProvider: { manager.dragPayload(for: entry.date, taskID: $0) },
                    onToggle: { manager.toggleTaskCompletion(on: entry.date, taskID: $0) },
                    onTextChange: { manager.updateTaskText(on: entry.date, taskID: $0, text: $1) },
                    onNoteChange: { manager.updateNote(on: entry.date, taskID: $0, note: $1) },
                    onClear: { manager.clearTask(on: entry.date, taskID: $0) },
                    onDrop: { manager.handleDropPayload($0, to: entry.date) }
                )
                .tag(entry.date)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 236)
        .animation(.easeInOut(duration: 0.25), value: manager.selectedDate)
    }

    private var weeklySummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(manager.completionSummaryText)
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                ForEach(manager.weekSummary.dayBreakdown) { day in
                    Circle()
                        .fill(color(for: day))
                        .frame(width: 8, height: 8)
                        .help(summaryTooltip(for: day))
                }

                if let emoji = manager.averageMoodEmoji {
                    Text(emoji)
                        .font(.system(size: 12))
                        .transition(.opacity)
                        .help(manager.averageMoodTooltip ?? "")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(action: manager.triggerWindDownPrompt) {
                Label("Wind Down", systemImage: "moon.zzz.fill")
            }
            .buttonStyle(PanelButtonStyle())

            Button(action: openSettings) {
                Label("Settings", systemImage: "gear")
            }
            .buttonStyle(PanelButtonStyle())

            Button(action: quitApplication) {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(PanelButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func color(for day: WeekSummary.DayBreakdown) -> Color {
        if day.completed == 0 {
            return Color.gray.opacity(0.35)
        } else if day.completed == day.total {
            return Color.green.opacity(0.65)
        } else {
            return Color.yellow.opacity(0.6)
        }
    }

    private func summaryTooltip(for day: WeekSummary.DayBreakdown) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        let base = formatter.string(from: day.date)
        let completion = "\(day.completed) / \(day.total) tasks"
        if let mood = day.mood {
            return "\(base): \(completion), mood \(mood)"
        }
        return "\(base): \(completion)"
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

private struct PanelBackground: View {
    var body: some View {
        VisualEffectBlur(material: .menu, blendingMode: .withinWindow)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct PanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundColor(.primary.opacity(configuration.isPressed ? 0.5 : 0.75))
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.07 : 0.05))
            )
    }
}

private struct DayCardView: View {
    let entry: ToDoManager.DayEntry
    let highlightedTaskID: FocusTask.ID?
    let descriptor: String
    let focusState: FocusState<FocusTask.ID?>.Binding
    let isSelected: Bool
    let payloadProvider: (FocusTask.ID) -> String
    let onToggle: (FocusTask.ID) -> Void
    let onTextChange: (FocusTask.ID, String) -> Void
    let onNoteChange: (FocusTask.ID, String) -> Void
    let onClear: (FocusTask.ID) -> Void
    let onDrop: (String) -> Void

    @State private var isTargeted = false

    private static let headerFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.headerFormatter.string(from: entry.date))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary.opacity(0.75))
                    Text(descriptor)
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let mood = entry.snapshot.mood {
                    Text(moodEmoji(for: mood))
                        .font(.system(size: 16))
                        .transition(.opacity)
                        .help("Mood logged: \(mood)")
                }
            }

            VStack(spacing: 10) {
                ForEach(entry.snapshot.tasks) { task in
                    FocusTaskRow(
                        task: task,
                        isHighlighted: isSelected && highlightedTaskID == task.id,
                        onToggle: { onToggle(task.id) },
                        onTextChange: { onTextChange(task.id, $0) },
                        onNoteChange: { onNoteChange(task.id, $0) },
                        onClear: { onClear(task.id) }
                    )
                    .focused(focusState, equals: task.id)
                    .conditionalModifier(canDrag(task: task)) {
                        $0.onDrag { NSItemProvider(object: payloadProvider(task.id) as NSString) }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.12 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? Color.orange.opacity(0.35) : Color.white.opacity(0.05), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.orange.opacity(isTargeted ? 0.45 : 0), lineWidth: 2)
        )
        .animation(.easeInOut(duration: 0.25), value: isSelected)
        .animation(.easeInOut(duration: 0.2), value: isTargeted)
        .onDrop(of: [UTType.utf8PlainText], isTargeted: $isTargeted) { providers in
            guard isSelected else { return false }
            guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
            provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let payload = object as? String else { return }
                DispatchQueue.main.async {
                    onDrop(payload)
                }
            }
            return true
        }
    }

    private func canDrag(task: FocusTask) -> Bool {
        let trimmed = task.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !task.done
    }

    private func moodEmoji(for value: Int) -> String {
        switch value {
        case ..<2: return "😫"
        case 2: return "😕"
        case 3: return "😐"
        case 4: return "🙂"
        default: return "😄"
        }
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
        VStack(spacing: 16) {
            Text("How did your day feel today?")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.primary.opacity(0.85))

            HStack(spacing: 12) {
                ForEach(moods, id: \.0) { mood in
                    Button(action: { onSelectMood(mood.0) }) {
                        Text(mood.1)
                            .font(.system(size: 24))
                            .padding(10)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.12))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                }
            }

            Button("Maybe later", action: onCancel)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.14))
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(0.25))
                        .blur(radius: 30)
                )
        )
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
