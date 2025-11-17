import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var dayManager: DayManager
    @ObservedObject var toDoManager: ToDoManager

    var body: some View {
        TabView {
            GeneralSettingsView(dayManager: dayManager, toDoManager: toDoManager)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 520)
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var dayManager: DayManager
    @ObservedObject var toDoManager: ToDoManager
    @State private var selectedWeekday: Weekday = Weekday(rawValue: Calendar.current.component(.weekday, from: Date())) ?? .monday
    @State private var copyConfirmationMessage: String?
    @State private var copyConfirmationToken = UUID()

    var body: some View {
        Form {
            Section(header: Text("Schedule")) {
                Text("Build and reuse work blocks for each weekday. You can add, remove, or copy schedules between days and blocks automatically sort by start time.")
                    .font(.callout)
                    .foregroundColor(.secondary)

                WeekdaySelector(selectedWeekday: $selectedWeekday)

                PresetButtons(
                    applyPreset: applyPreset,
                    addBlock: { addBlock(for: selectedWeekday) }
                )

                WorkBlockListEditor(
                    blocks: binding(for: selectedWeekday),
                    validationMessages: validationMessages(for: selectedWeekday),
                    removeBlock: { removeBlock(for: selectedWeekday, at: $0) }
                )

                HStack(spacing: 12) {
                    CopyScheduleMenu(
                        selectedWeekday: selectedWeekday,
                        copyAction: copySchedule(from:to:),
                        hasBlocks: !(dayManager.workBlocks[selectedWeekday]?.isEmpty ?? true)
                    )

                    if let message = copyConfirmationMessage {
                        Label(message, systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.callout)
                    }

                    Spacer()
                }
            }

            Section(header: Text("Display")) {
                Toggle("Show value next to the bar", isOn: $dayManager.showMenuValue)

                Picker("Value format", selection: $dayManager.displayMode) {
                    ForEach(DayDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 8) {
                    Text(dayManagerDescription)
                        .font(.callout)
                        .foregroundColor(.secondary)

                    Divider()

                    Text("Block Reminders")
                        .font(.headline)
                    Text("Gently pulse the screen edges near the end of each block.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)

                ForEach(BlockReminderStage.allCases) { stage in
                    reminderRow(for: stage)
                }

                Button("Restore default reminder colors") {
                    dayManager.reminderPreferences = .default
                }
            }

            Section(header: Text("Overflow")) {
                Toggle("Keep overflow open between sessions", isOn: $dayManager.persistOverflowState)

                Text("Enable this if you use the overflow list frequently. When disabled, overflow is always collapsed when you open the panel.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("Inbox")) {
                Toggle("Keep inbox open between sessions", isOn: $toDoManager.keepInboxPanelOpenBetweenSessions)

                Text("When disabled, the inbox drawer stays hidden until you open it each time.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("Notes")) {
                Toggle("Keep inline notes open between sessions", isOn: $toDoManager.keepNotesPanelOpenBetweenSessions)

                Toggle("Open notes in floating window by default", isOn: $toDoManager.openNotesInFloatingByDefault)

                Text("When enabled, inline notes stay open the next time you open the panel. You can also jump straight to the detached notes window each time.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("Panel Defaults")) {
                Toggle("Open recent day", isOn: $toDoManager.openRecentDayOnLaunch)

                Toggle("Open recent note", isOn: $toDoManager.openRecentNoteOnLaunch)

                Text("Enable these to reopen the last day or note you viewed instead of jumping straight to today.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var dayManagerDescription: String {
        if dayManager.isActive {
            return dayManager.displayText.isEmpty
                ? "DayDrain stays visible during active blocks and updates as your schedule progresses."
                : dayManager.displayText
        }

        if !dayManager.displayText.isEmpty {
            return dayManager.displayText
        }

        return "Pick a weekday to adjust its blocks. The menu bar item will stay available before, during, and after the hours you set."
    }

    private func reminderRow(for stage: BlockReminderStage) -> some View {
        HStack(spacing: 12) {
            Toggle(stage.label, isOn: binding(for: stage))

            Spacer()

            ColorWellPicker(color: nsColorBinding(for: stage))
                .frame(width: 40, height: 24)

            Button("Test") {
                dayManager.previewReminder(for: stage)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func binding(for weekday: Weekday) -> Binding<[WorkBlock]> {
        Binding(
            get: { dayManager.workBlocks[weekday] ?? [] },
            set: { newValue in assignBlocks(newValue, to: weekday) }
        )
    }

    private func binding(for stage: BlockReminderStage) -> Binding<Bool> {
        Binding(
            get: { dayManager.reminderPreferences.enabledStageIDs.contains(stage) },
            set: { isOn in
                var preferences = dayManager.reminderPreferences
                if isOn {
                    preferences.enabledStageIDs.insert(stage)
                } else {
                    preferences.enabledStageIDs.remove(stage)
                }
                dayManager.reminderPreferences = preferences
            }
        )
    }

    private func nsColorBinding(for stage: BlockReminderStage) -> Binding<NSColor> {
        Binding(
            get: { dayManager.reminderPreferences.color(for: stage) },
            set: { newColor in
                var preferences = dayManager.reminderPreferences
                preferences.customColors[stage] = RGBAColor(nsColor: newColor)
                dayManager.reminderPreferences = preferences
            }
        )
    }

    private func addBlock(for weekday: Weekday) {
        var blocks = dayManager.workBlocks[weekday] ?? []
        let newBlock = suggestedBlock(after: blocks.last)
        blocks.append(newBlock)
        assignBlocks(blocks, to: weekday)
    }

    private func removeBlock(for weekday: Weekday, at index: Int) {
        guard var blocks = dayManager.workBlocks[weekday], blocks.indices.contains(index) else { return }
        blocks.remove(at: index)
        assignBlocks(blocks, to: weekday)
    }

    private func suggestedBlock(after block: WorkBlock?) -> WorkBlock {
        guard let block else {
            let start = TimeComponents(hour: 9, minute: 0)
            let end = TimeComponents(hour: 10, minute: 0)
            return WorkBlock(start: start, end: end)
        }

        let nextStartMinutes = min(23 * 60, block.end.totalMinutes + 30)
        let nextEndMinutes = min(23 * 60 + 59, nextStartMinutes + 60)
        let start = TimeComponents(hour: nextStartMinutes / 60, minute: nextStartMinutes % 60)
        let end = TimeComponents(hour: nextEndMinutes / 60, minute: nextEndMinutes % 60)
        return WorkBlock(start: start, end: end)
    }

    private func applyPreset(_ presetBlocks: [WorkBlock]) {
        assignBlocks(presetBlocks, to: selectedWeekday)
    }

    private func copySchedule(from source: Weekday, to destination: Weekday) {
        guard let blocks = dayManager.workBlocks[source] else { return }
        assignBlocks(blocks, to: destination)
        showCopyConfirmation(from: source, to: destination)
    }

    private func validationMessages(for weekday: Weekday) -> [String] {
        guard let blocks = dayManager.workBlocks[weekday], !blocks.isEmpty else { return [] }
        let sorted = blocks.sorted { $0.start.totalMinutes < $1.start.totalMinutes }
        var messages: [String] = []

        for (index, block) in sorted.enumerated() {
            if !block.isValid {
                messages.append("Block \(index + 1) ends before it starts.")
            }

            if index > 0 {
                let previous = sorted[index - 1]
                if block.start.totalMinutes < previous.end.totalMinutes {
                    messages.append("Blocks \(index) and \(index + 1) overlap.")
                }
            }
        }

        return messages
    }

    private func assignBlocks(_ blocks: [WorkBlock], to weekday: Weekday) {
        var schedule = dayManager.workBlocks
        schedule[weekday] = blocks
        dayManager.workBlocks = schedule
    }

    private func showCopyConfirmation(from source: Weekday, to destination: Weekday) {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        let sourceName = formatter.weekdaySymbols[(source.rawValue - 1) % formatter.weekdaySymbols.count]
        let destinationName = formatter.weekdaySymbols[(destination.rawValue - 1) % formatter.weekdaySymbols.count]

        copyConfirmationToken = UUID()
        copyConfirmationMessage = "Copied \(sourceName) to \(destinationName)"

        Task { @MainActor in
            let currentToken = copyConfirmationToken
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if currentToken == copyConfirmationToken {
                copyConfirmationMessage = nil
            }
        }
    }
}

private struct WeekdaySelector: View {
    @Binding var selectedWeekday: Weekday

    var body: some View {
        Picker("Weekday", selection: $selectedWeekday) {
            ForEach(Weekday.allCases) { weekday in
                Text(weekday.localizedName).tag(weekday)
            }
        }
        .pickerStyle(.segmented)
        .padding(.bottom, 4)
    }
}

private struct PresetButtons: View {
    var applyPreset: ([WorkBlock]) -> Void
    var addBlock: () -> Void

    private var presets: [PresetDefinition] {
        [
            PresetDefinition(
                id: "classic",
                title: "Classic 9–5",
                blocks: [
                    .fromHours(startHour: 9, startMinute: 0, endHour: 17, endMinute: 0)
                ]
            ),
            PresetDefinition(
                id: "amPmSplit",
                title: "AM/PM Split",
                blocks: [
                    .fromHours(startHour: 9, startMinute: 0, endHour: 12, endMinute: 0),
                    .fromHours(startHour: 13, startMinute: 0, endHour: 17, endMinute: 0)
                ]
            ),
            PresetDefinition(
                id: "shortSprints",
                title: "Short Sprints",
                blocks: [
                    .fromHours(startHour: 9, startMinute: 0, endHour: 10, endMinute: 30),
                    .fromHours(startHour: 11, startMinute: 0, endHour: 12, endMinute: 30),
                    .fromHours(startHour: 13, startMinute: 30, endHour: 17, endMinute: 0)
                ]
            )
        ]
    }

    var body: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(presets) { preset in
                    Button(preset.title) {
                        applyPreset(preset.blocks)
                    }
                }
            } label: {
                Label("Apply preset", systemImage: "calendar.badge.plus")
            }

            Button(action: addBlock) {
                Label("Add block", systemImage: "plus.circle")
            }
        }
    }

    private struct PresetDefinition: Identifiable {
        let id: String
        let title: String
        let blocks: [WorkBlock]
    }
}

private struct WorkBlockListEditor: View {
    @Binding var blocks: [WorkBlock]
    var validationMessages: [String]
    var removeBlock: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if blocks.isEmpty {
                Text("No blocks for this day yet. Add one to get started.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(blocks.enumerated()), id: \.element.id) { index, _ in
                    WorkBlockRow(
                        index: index,
                        block: Binding(
                            get: { blocks[index] },
                            set: { blocks[index] = $0 }
                        ),
                        remove: { removeBlock(index) }
                    )
                }
            }

            if !validationMessages.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(validationMessages, id: \.self) { message in
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}

private struct WorkBlockRow: View {
    let index: Int
    @Binding var block: WorkBlock
    var remove: () -> Void

    private var startBinding: Binding<Date> {
        Binding(
            get: { block.start.asDate() },
            set: { newValue in block.start = TimeComponents.from(date: newValue) }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { block.end.asDate() },
            set: { newValue in block.end = TimeComponents.from(date: newValue) }
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("Block \(index + 1)")
                .font(.subheadline)
                .frame(width: 70, alignment: .leading)

            DatePicker("Start", selection: startBinding, displayedComponents: .hourAndMinute)
                .labelsHidden()

            DatePicker("End", selection: endBinding, displayedComponents: .hourAndMinute)
                .labelsHidden()

            Button(role: .destructive, action: remove) {
                Image(systemName: "trash")
            }
            .help("Remove block \(index + 1)")
        }
    }
}

private struct CopyScheduleMenu: View {
    var selectedWeekday: Weekday
    var copyAction: (Weekday, Weekday) -> Void
    var hasBlocks: Bool

    private var otherWeekdays: [Weekday] {
        Weekday.allCases.filter { $0 != selectedWeekday }
    }

    var body: some View {
        Menu {
            if hasBlocks {
                Section("Copy selected into…") {
                    ForEach(otherWeekdays) { target in
                        Button(target.localizedName) {
                            copyAction(selectedWeekday, target)
                        }
                    }
                }
            }

            Section("Replace selected with…") {
                ForEach(otherWeekdays) { source in
                    Button(source.localizedName) {
                        copyAction(source, selectedWeekday)
                    }
                }
            }
        } label: {
            Label("Copy schedule", systemImage: "square.on.square")
        }
        .disabled(otherWeekdays.isEmpty)
    }
}

private struct ColorWellPicker: NSViewRepresentable {
    @Binding var color: NSColor

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSColorWell {
        let well = NSColorWell()
        well.isBordered = true
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorDidChange(_:))
        well.color = color
        return well
    }

    func updateNSView(_ nsView: NSColorWell, context: Context) {
        guard nsView.color != color else { return }
        nsView.color = color
    }

    final class Coordinator: NSObject {
        var parent: ColorWellPicker

        init(_ parent: ColorWellPicker) {
            self.parent = parent
        }

        @objc func colorDidChange(_ sender: NSColorWell) {
            parent.color = sender.color
        }
    }
}

private struct AboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("DayDrain").font(.title).bold()
            Text("Designed to keep your focus blocks intentional and calm. Configure daily schedules, track progress in the menu bar, and wind down with gentle reminders.")
                .font(.body)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding()
    }
}

private extension TimeComponents {
    func asDate() -> Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components) ?? Date()
    }
}

private extension WorkBlock {
    static func fromHours(startHour: Int, startMinute: Int, endHour: Int, endMinute: Int) -> WorkBlock {
        WorkBlock(
            start: TimeComponents(hour: startHour, minute: startMinute),
            end: TimeComponents(hour: endHour, minute: endMinute)
        )
    }
}
