import SwiftUI

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

    var body: some View {
        Form {
            Section(header: Text("Schedule")) {
                Text("Build and reuse work blocks for each weekday. You can add, remove, reorder, or copy schedules between days.")
                    .font(.callout)
                    .foregroundColor(.secondary)

                WeekdaySelector(selectedWeekday: $selectedWeekday)

                PresetButtons(applyPreset: applyPreset)

                WorkBlockListEditor(
                    blocks: binding(for: selectedWeekday),
                    validationMessages: validationMessages(for: selectedWeekday),
                    addBlock: { addBlock(for: selectedWeekday) },
                    moveBlock: { from, offset in moveBlock(for: selectedWeekday, from: from, offset: offset) },
                    removeBlock: { removeBlock(for: selectedWeekday, at: $0) }
                )

                CopyScheduleMenu(
                    selectedWeekday: selectedWeekday,
                    copyAction: copySchedule(from:to:),
                    hasBlocks: !(dayManager.workBlocks[selectedWeekday]?.isEmpty ?? true)
                )
            }

            Section(header: Text("Display")) {
                Toggle("Show value next to the bar", isOn: $dayManager.showMenuValue)

                Picker("Value format", selection: $dayManager.displayMode) {
                    ForEach(DayDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(dayManagerDescription)
                    .font(.callout)
                    .foregroundColor(.secondary)
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

    private func binding(for weekday: Weekday) -> Binding<[WorkBlock]> {
        Binding(
            get: { dayManager.workBlocks[weekday] ?? [] },
            set: { newValue in
                if newValue.isEmpty {
                    dayManager.workBlocks.removeValue(forKey: weekday)
                } else {
                    dayManager.workBlocks[weekday] = newValue
                }
            }
        )
    }

    private func addBlock(for weekday: Weekday) {
        var blocks = dayManager.workBlocks[weekday] ?? []
        let newBlock = suggestedBlock(after: blocks.last)
        blocks.append(newBlock)
        dayManager.workBlocks[weekday] = blocks
    }

    private func moveBlock(for weekday: Weekday, from index: Int, offset: Int) {
        guard var blocks = dayManager.workBlocks[weekday], blocks.indices.contains(index) else { return }
        let newIndex = index + offset
        guard blocks.indices.contains(newIndex) else { return }
        let block = blocks.remove(at: index)
        blocks.insert(block, at: newIndex)
        dayManager.workBlocks[weekday] = blocks
    }

    private func removeBlock(for weekday: Weekday, at index: Int) {
        guard var blocks = dayManager.workBlocks[weekday], blocks.indices.contains(index) else { return }
        blocks.remove(at: index)
        if blocks.isEmpty {
            dayManager.workBlocks.removeValue(forKey: weekday)
        } else {
            dayManager.workBlocks[weekday] = blocks
        }
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
        dayManager.workBlocks[selectedWeekday] = presetBlocks
    }

    private func copySchedule(from source: Weekday, to destination: Weekday) {
        guard let blocks = dayManager.workBlocks[source] else { return }
        dayManager.workBlocks[destination] = blocks
    }

    private func validationMessages(for weekday: Weekday) -> [String] {
        guard let blocks = dayManager.workBlocks[weekday], !blocks.isEmpty else { return [] }
        let sorted = blocks.sorted { $0.start.totalMinutes < $1.start.totalMinutes }
        var messages: [String] = []

        for (index, block) in sorted.enumerated() {
            if !block.isValid {
                let label = block.label?.isEmpty == false ? "\(block.label!) " : ""
                messages.append("\(label)block \(index + 1) ends before it starts.")
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
}

private struct WeekdaySelector: View {
    @Binding var selectedWeekday: Weekday

    var body: some View {
        Picker("Weekday", selection: $selectedWeekday) {
            ForEach(Weekday.allCases) { weekday in
                Text(weekday.localizedName.prefix(3)).tag(weekday)
            }
        }
        .pickerStyle(.segmented)
    }
}

private struct PresetButtons: View {
    var applyPreset: ([WorkBlock]) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button("Full day") {
                let start = TimeComponents(hour: 9, minute: 0)
                let end = TimeComponents(hour: 17, minute: 0)
                applyPreset([WorkBlock(start: start, end: end)])
            }

            Button("Split AM/PM") {
                applyPreset(splitPreset)
            }

            Button("Triple block") {
                applyPreset(triplePreset)
            }
        }
    }

    private var splitPreset: [WorkBlock] {
        [
            WorkBlock(start: .init(hour: 9, minute: 0), end: .init(hour: 12, minute: 0), label: "Morning"),
            WorkBlock(start: .init(hour: 13, minute: 0), end: .init(hour: 17, minute: 0), label: "Afternoon")
        ]
    }

    private var triplePreset: [WorkBlock] {
        [
            WorkBlock(start: .init(hour: 9, minute: 0), end: .init(hour: 11, minute: 30), label: "Block 1"),
            WorkBlock(start: .init(hour: 12, minute: 30), end: .init(hour: 15, minute: 0), label: "Block 2"),
            WorkBlock(start: .init(hour: 15, minute: 30), end: .init(hour: 17, minute: 30), label: "Block 3")
        ]
    }
}

private struct WorkBlockListEditor: View {
    @Binding var blocks: [WorkBlock]
    var validationMessages: [String]
    var addBlock: () -> Void
    var moveBlock: (_ index: Int, _ offset: Int) -> Void
    var removeBlock: (_ index: Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if blocks.isEmpty {
                Text("No blocks for this day. Add one to begin scheduling.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                WorkBlockRow(
                    block: binding(for: block.id),
                    canMoveUp: index > 0,
                    canMoveDown: index < blocks.count - 1,
                    moveUp: { moveBlock(index, -1) },
                    moveDown: { moveBlock(index, 1) },
                    remove: { removeBlock(index) }
                )
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
            }

            if !validationMessages.isEmpty {
                ForEach(validationMessages, id: \.self) { message in
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.callout)
                }
            }

            HStack {
                Button(action: addBlock) {
                    Label("Add block", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                Spacer()
            }
        }
    }

    private func binding(for id: UUID) -> Binding<WorkBlock> {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else {
            return .constant(WorkBlock(start: .init(hour: 9, minute: 0), end: .init(hour: 10, minute: 0)))
        }

        return Binding(
            get: { blocks[index] },
            set: { blocks[index] = $0 }
        )
    }
}

private struct WorkBlockRow: View {
    @Binding var block: WorkBlock
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Label (optional)", text: labelBinding)
                Spacer()
                Button(action: remove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
            }

            HStack {
                DatePicker("Start", selection: startBinding, displayedComponents: .hourAndMinute)
                DatePicker("End", selection: endBinding, displayedComponents: .hourAndMinute)
            }

            HStack {
                Spacer()
                MoveButton(label: "Move up", systemImage: "arrow.up", action: moveUp)
                    .disabled(!canMoveUp)
                MoveButton(label: "Move down", systemImage: "arrow.down", action: moveDown)
                    .disabled(!canMoveDown)
            }
        }
    }

    private var labelBinding: Binding<String> {
        Binding(
            get: { block.label ?? "" },
            set: { newValue in
                block.label = newValue.isEmpty ? nil : newValue
            }
        )
    }

    private var startBinding: Binding<Date> {
        Binding(
            get: { block.start.date(on: Date()) ?? Date() },
            set: { newValue in
                block.start = TimeComponents.from(date: newValue)
            }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { block.end.date(on: Date()) ?? Date() },
            set: { newValue in
                block.end = TimeComponents.from(date: newValue)
            }
        )
    }
}

private struct MoveButton: View {
    let label: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 20, height: 20)
                .accessibilityLabel(label)
        }
        .buttonStyle(.borderless)
    }
}

private struct CopyScheduleMenu: View {
    let selectedWeekday: Weekday
    let copyAction: (Weekday, Weekday) -> Void
    let hasBlocks: Bool

    var body: some View {
        Menu("Copy to…") {
            ForEach(Weekday.allCases.filter { $0 != selectedWeekday }) { weekday in
                Button(weekday.localizedName) {
                    copyAction(selectedWeekday, weekday)
                }
            }
        }
        .disabled(!hasBlocks)
    }
}

private struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.fill")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)

            Text("DayDrain")
                .font(.title)
                .fontWeight(.bold)

            Text("Version 1.0")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("A menu bar app that visualizes your workday progress")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 60)

            Divider()
                .padding(.horizontal, 60)

            Text("Made with ❤️ using SwiftUI")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(dayManager: DayManager(), toDoManager: ToDoManager())
            .frame(width: 360)
    }
}
