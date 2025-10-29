import Foundation
import Combine
import SwiftUI

@MainActor
final class ToDoManager: ObservableObject {
    struct DayEntry: Identifiable {
        var date: Date
        var snapshot: DailyFocusSnapshot

        var id: String { snapshot.date }
    }

    @Published private(set) var dayEntries: [DayEntry]
    @Published private(set) var selectedDate: Date
    @Published private(set) var selectedDayMood: Int?
    @Published private(set) var weekSummary: WeekSummary
    @Published private(set) var pulseToken: Int
    @Published private(set) var allTasksCompleted: Bool
    @Published private(set) var overflowTasks: [OverflowTask]
    @Published private(set) var isOverflowCollapsed: Bool
    @Published private(set) var inboxTasks: [InboxTask]
    @Published private(set) var isInboxCollapsed: Bool
    @Published var focusedTaskID: FocusTask.ID?
    @Published var focusedOverflowIndex: Int?
    @Published var focusedInboxIndex: Int?
    @Published var isInboxPanelVisible: Bool
    @Published var isWindDownPromptVisible: Bool

    var onTaskDone: ((FocusTask, Date) -> Void)?
    var onTaskMoved: ((FocusTask, Date, Date) -> Void)?
    var onMoodLogged: ((Int, Date) -> Void)?

    var tooltip: String { "Tackle the hardest one first." }

    var highlightedTaskID: FocusTask.ID? {
        let tasks = tasks(for: selectedDate)
        return tasks.first(where: { !$0.done && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.id
            ?? tasks.first?.id
    }

    var completionSummaryText: String { weekSummary.completionText }
    var averageMoodEmoji: String? { weekSummary.averageMoodEmoji }
    var averageMoodTooltip: String? { weekSummary.averageMoodTooltip }

    var weekDates: [Date] { dayEntries.map { $0.date } }

    private let weekManager: WeekManager
    private let overflowManager: OverflowManager
    private let inboxManager: InboxManager
    private var midnightTimer: Timer?
    private var currentDay: Date
    private var calendar = Calendar.current

    private lazy var isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private lazy var navFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        formatter.locale = Locale.current
        return formatter
    }()

    init(weekManager: WeekManager = WeekManager()) {
        self.weekManager = weekManager
        self.overflowManager = OverflowManager(weekManager: weekManager)
        self.inboxManager = InboxManager()
        self.currentDay = Self.startOfDay(for: Date())
        self.selectedDate = currentDay
        self.weekSummary = .empty
        self.pulseToken = 0
        self.allTasksCompleted = false
        self.dayEntries = []
        self.overflowTasks = []
        self.isOverflowCollapsed = true
        self.inboxTasks = []
        self.isInboxCollapsed = false
        self.isWindDownPromptVisible = false
        self.isInboxPanelVisible = false
        self.selectedDayMood = nil
        self.focusedOverflowIndex = nil
        self.focusedInboxIndex = nil

        ensureCurrentWeekLoaded()
        scheduleMidnightRefresh()
    }

    deinit {
        midnightTimer?.invalidate()
    }

    func descriptor(for date: Date) -> String {
        if calendar.isDateInToday(date) {
            return "Today · \(navFormatter.string(from: date))"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow · \(navFormatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday · \(navFormatter.string(from: date))"
        } else {
            return navFormatter.string(from: date)
        }
    }

    func select(date: Date) {
        guard let index = indexOfDay(date) else { return }
        selectedDate = dayEntries[index].date
        focusedTaskID = nil
        focusedOverflowIndex = nil
        focusedInboxIndex = nil
        updateSelectionState()
    }

    func goToPreviousDay() {
        guard let currentIndex = indexOfDay(selectedDate), currentIndex > 0 else { return }
        selectedDate = dayEntries[currentIndex - 1].date
        focusedTaskID = nil
        focusedOverflowIndex = nil
        focusedInboxIndex = nil
        updateSelectionState()
    }

    func goToNextDay() {
        guard let currentIndex = indexOfDay(selectedDate), currentIndex < dayEntries.count - 1 else { return }
        selectedDate = dayEntries[currentIndex + 1].date
        focusedTaskID = nil
        focusedOverflowIndex = nil
        focusedInboxIndex = nil
        updateSelectionState()
    }

    func tasks(for date: Date) -> [FocusTask] {
        guard let index = indexOfDay(date) else { return [] }
        return dayEntries[index].snapshot.tasks
    }

    func mood(for date: Date) -> Int? {
        guard let index = indexOfDay(date) else { return nil }
        return dayEntries[index].snapshot.mood
    }

    func toggleTaskCompletion(on date: Date, taskID: FocusTask.ID) {
        guard let dayIndex = indexOfDay(date),
              let taskIndex = dayEntries[dayIndex].snapshot.tasks.firstIndex(where: { $0.id == taskID }) else { return }

        dayEntries[dayIndex].snapshot.tasks[taskIndex].done.toggle()
        if dayEntries[dayIndex].snapshot.tasks[taskIndex].done {
            pulseToken += 1
            onTaskDone?(dayEntries[dayIndex].snapshot.tasks[taskIndex], date)
        }
        weekManager.save(snapshot: dayEntries[dayIndex].snapshot)
        updateSelectionState()
        updateSummary()
    }

    func updateTaskText(on date: Date, taskID: FocusTask.ID, text: String) {
        guard let dayIndex = indexOfDay(date),
              let taskIndex = dayEntries[dayIndex].snapshot.tasks.firstIndex(where: { $0.id == taskID }) else { return }

        let trimmed = String(text.prefix(80))
        dayEntries[dayIndex].snapshot.tasks[taskIndex].text = trimmed
        if trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            dayEntries[dayIndex].snapshot.tasks[taskIndex].done = false
            dayEntries[dayIndex].snapshot.tasks[taskIndex].note = ""
        }
        weekManager.save(snapshot: dayEntries[dayIndex].snapshot)
        updateSelectionState()
        updateSummary()
    }

    func updateNote(on date: Date, taskID: FocusTask.ID, note: String) {
        guard let dayIndex = indexOfDay(date),
              let taskIndex = dayEntries[dayIndex].snapshot.tasks.firstIndex(where: { $0.id == taskID }) else { return }

        dayEntries[dayIndex].snapshot.tasks[taskIndex].note = String(note.prefix(200))
        weekManager.save(snapshot: dayEntries[dayIndex].snapshot)
    }

    func clearTask(on date: Date, taskID: FocusTask.ID) {
        guard let dayIndex = indexOfDay(date),
              let taskIndex = dayEntries[dayIndex].snapshot.tasks.firstIndex(where: { $0.id == taskID }) else { return }

        dayEntries[dayIndex].snapshot.tasks[taskIndex].text = ""
        dayEntries[dayIndex].snapshot.tasks[taskIndex].note = ""
        dayEntries[dayIndex].snapshot.tasks[taskIndex].done = false
        weekManager.save(snapshot: dayEntries[dayIndex].snapshot)
        updateSelectionState()
        updateSummary()
    }

    @discardableResult
    func quickAddTask() -> Bool {
        guard let dayIndex = indexOfDay(selectedDate) else { return false }
        if let slot = dayEntries[dayIndex].snapshot.tasks.firstIndex(where: { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            dayEntries[dayIndex].snapshot.tasks[slot].done = false
            weekManager.save(snapshot: dayEntries[dayIndex].snapshot)
            focusedTaskID = dayEntries[dayIndex].snapshot.tasks[slot].id
            updateSelectionState()
            updateSummary()
            return true
        }
        return false
    }

    // MARK: - Overflow

    func resetOverflowToCollapsed() {
        // Update the published state immediately
        isOverflowCollapsed = true
        focusedOverflowIndex = nil
        
        // Also update the persisted state if the day entry exists
        if let dayIndex = indexOfDay(selectedDate) {
            let updatedState = overflowManager.setCollapsed(true, on: selectedDate)
            dayEntries[dayIndex].snapshot.uiState = updatedState
            synchronizeSnapshot(for: selectedDate)
        }
    }

    func toggleOverflowCollapsed() {
        guard let dayIndex = indexOfDay(selectedDate) else { return }
        let newValue = !dayEntries[dayIndex].snapshot.uiState.isOverflowCollapsed
        let updatedState = overflowManager.setCollapsed(newValue, on: selectedDate)
        dayEntries[dayIndex].snapshot.uiState = updatedState
        synchronizeSnapshot(for: selectedDate)
        updateSelectionState()
        if updatedState.isOverflowCollapsed {
            focusedOverflowIndex = nil
        }
    }

    func addOverflowTask() {
        guard indexOfDay(selectedDate) != nil else { return }
        if isOverflowCollapsed {
            let updatedState = overflowManager.setCollapsed(false, on: selectedDate)
            if let dayIndex = indexOfDay(selectedDate) {
                dayEntries[dayIndex].snapshot.uiState = updatedState
            }
        }
        overflowManager.updateTasks(on: selectedDate) { tasks in
            tasks.append(OverflowTask(text: "", done: false))
        }
        synchronizeSnapshot(for: selectedDate)
        updateSelectionState()
        focusedOverflowIndex = overflowTasks.indices.last
    }

    func updateOverflowTaskText(at index: Int, text: String) {
        guard index >= 0 else { return }
        overflowManager.updateTasks(on: selectedDate) { tasks in
            guard tasks.indices.contains(index) else { return }
            tasks[index].text = text
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                tasks[index].done = false
            }
        }
        synchronizeSnapshot(for: selectedDate)
        updateSelectionState()
    }

    func toggleOverflowTaskDone(at index: Int) {
        overflowManager.updateTasks(on: selectedDate) { tasks in
            guard tasks.indices.contains(index) else { return }
            tasks[index].done.toggle()
        }
        synchronizeSnapshot(for: selectedDate)
        updateSelectionState()
    }

    func removeOverflowTask(at index: Int) {
        overflowManager.updateTasks(on: selectedDate) { tasks in
            guard tasks.indices.contains(index) else { return }
            tasks.remove(at: index)
        }
        synchronizeSnapshot(for: selectedDate)
        updateSelectionState()
        if let focusedIndex = focusedOverflowIndex {
            if focusedIndex == index {
                focusedOverflowIndex = nil
            } else if focusedIndex > index {
                focusedOverflowIndex = focusedIndex - 1
            }
        }
    }

    @discardableResult
    func promoteOverflowTaskToFocus(at index: Int) -> Bool {
        guard let dayIndex = indexOfDay(selectedDate) else { return false }
        guard overflowTasks.indices.contains(index) else { return false }
        let overflowTask = overflowTasks[index]
        let trimmed = overflowTask.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        var snapshot = dayEntries[dayIndex].snapshot
        guard let slotIndex = snapshot.tasks.firstIndex(where: { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return false
        }

        snapshot.tasks[slotIndex].text = String(trimmed.prefix(80))
        snapshot.tasks[slotIndex].note = ""
        snapshot.tasks[slotIndex].done = false

        if snapshot.overflow.indices.contains(index) {
            snapshot.overflow.remove(at: index)
        }

        dayEntries[dayIndex].snapshot = snapshot
        weekManager.save(snapshot: snapshot)
        synchronizeSnapshot(for: selectedDate)
        updateSelectionState()
        focusedTaskID = snapshot.tasks[slotIndex].id
        focusedOverflowIndex = nil
        updateSummary()
        return true
    }

    @discardableResult
    func moveOverflowTaskToInbox(at index: Int, priority: InboxPriority = .medium) -> Bool {
        guard overflowTasks.indices.contains(index) else { return false }
        let task = overflowTasks[index]
        let trimmed = task.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        overflowManager.updateTasks(on: selectedDate) { tasks in
            guard tasks.indices.contains(index) else { return }
            tasks.remove(at: index)
        }

        inboxManager.update { state in
            if state.isCollapsed {
                state.isCollapsed = false
            }
            state.tasks.append(InboxTask(text: trimmed, priority: priority, done: false))
        }

        synchronizeSnapshot(for: selectedDate)
        updateSelectionState()
        focusedInboxIndex = inboxTasks.indices.last
        focusedOverflowIndex = nil
        return true
    }

    // MARK: - Inbox

    func toggleInboxPanelVisibility() {
        isInboxPanelVisible.toggle()
        if !isInboxPanelVisible {
            focusedInboxIndex = nil
        }
    }

    func hideInboxPanel() {
        isInboxPanelVisible = false
        focusedInboxIndex = nil
    }

    func toggleInboxCollapsed() {
        let updated = inboxManager.update { state in
            state.isCollapsed.toggle()
        }
        inboxTasks = updated.tasks
        isInboxCollapsed = updated.isCollapsed
        if updated.isCollapsed {
            focusedInboxIndex = nil
        }
    }

    func addInboxTask(priority: InboxPriority = .medium) {
        let updated = inboxManager.update { state in
            if state.isCollapsed {
                state.isCollapsed = false
            }
            state.tasks.append(InboxTask(text: "", priority: priority, done: false))
        }
        inboxTasks = updated.tasks
        isInboxCollapsed = updated.isCollapsed
        focusedInboxIndex = inboxTasks.indices.last
    }

    func updateInboxTaskText(at index: Int, text: String) {
        let updated = inboxManager.update { state in
            guard state.tasks.indices.contains(index) else { return }
            state.tasks[index].text = text
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                state.tasks[index].done = false
            }
        }
        inboxTasks = updated.tasks
        isInboxCollapsed = updated.isCollapsed
    }

    func setInboxPriority(at index: Int, priority: InboxPriority) {
        let updated = inboxManager.update { state in
            guard state.tasks.indices.contains(index) else { return }
            state.tasks[index].priority = priority
        }
        inboxTasks = updated.tasks
        isInboxCollapsed = updated.isCollapsed
    }

    func toggleInboxTaskDone(at index: Int) {
        let updated = inboxManager.update { state in
            guard state.tasks.indices.contains(index) else { return }
            state.tasks[index].done.toggle()
        }
        inboxTasks = updated.tasks
        isInboxCollapsed = updated.isCollapsed
    }

    func removeInboxTask(at index: Int) {
        let updated = inboxManager.update { state in
            guard state.tasks.indices.contains(index) else { return }
            state.tasks.remove(at: index)
        }
        inboxTasks = updated.tasks
        isInboxCollapsed = updated.isCollapsed
        if let focusedIndex = focusedInboxIndex {
            if focusedIndex == index {
                focusedInboxIndex = nil
            } else if focusedIndex > index {
                let newCount = inboxTasks.count
                let candidate = focusedIndex - 1
                focusedInboxIndex = candidate < newCount ? candidate : nil
            }
        }
    }

    @discardableResult
    func moveInboxTaskToFocus(at index: Int) -> Bool {
        guard let dayIndex = indexOfDay(selectedDate) else { return false }
        guard inboxTasks.indices.contains(index) else { return false }
        let task = inboxTasks[index]
        let trimmed = task.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let slotIndex = dayEntries[dayIndex].snapshot.tasks.firstIndex(where: { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return false
        }

        let updated = inboxManager.update { state in
            guard state.tasks.indices.contains(index) else { return }
            state.tasks.remove(at: index)
        }

        dayEntries[dayIndex].snapshot.tasks[slotIndex].text = String(trimmed.prefix(80))
        dayEntries[dayIndex].snapshot.tasks[slotIndex].note = ""
        dayEntries[dayIndex].snapshot.tasks[slotIndex].done = false
        weekManager.save(snapshot: dayEntries[dayIndex].snapshot)

        inboxTasks = updated.tasks
        isInboxCollapsed = updated.isCollapsed
        synchronizeSnapshot(for: selectedDate)
        updateSelectionState()
        focusedTaskID = dayEntries[dayIndex].snapshot.tasks[slotIndex].id
        focusedInboxIndex = nil
        updateSummary()
        return true
    }

    @discardableResult
    func moveInboxTaskToOverflow(at index: Int) -> Bool {
        guard inboxTasks.indices.contains(index) else { return false }
        let task = inboxTasks[index]
        let trimmed = task.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let updatedState = inboxManager.update { state in
            guard state.tasks.indices.contains(index) else { return }
            state.tasks.remove(at: index)
        }

        overflowManager.updateTasks(on: selectedDate) { tasks in
            tasks.append(OverflowTask(text: trimmed, done: false))
        }

        inboxTasks = updatedState.tasks
        isInboxCollapsed = updatedState.isCollapsed
        synchronizeSnapshot(for: selectedDate)
        updateSelectionState()
        focusedOverflowIndex = overflowTasks.indices.last
        focusedInboxIndex = nil
        return true
    }

    @discardableResult
    func demoteFocusedTaskToOverflow() -> Bool {
        guard let taskID = focusedTaskID, let dayIndex = indexOfDay(selectedDate) else { return false }
        guard let taskIndex = dayEntries[dayIndex].snapshot.tasks.firstIndex(where: { $0.id == taskID }) else { return false }
        let task = dayEntries[dayIndex].snapshot.tasks[taskIndex]
        let trimmed = task.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        overflowManager.updateTasks(on: selectedDate) { tasks in
            tasks.append(OverflowTask(text: trimmed, done: false))
        }

        dayEntries[dayIndex].snapshot.tasks[taskIndex].text = ""
        dayEntries[dayIndex].snapshot.tasks[taskIndex].note = ""
        dayEntries[dayIndex].snapshot.tasks[taskIndex].done = false
        weekManager.save(snapshot: dayEntries[dayIndex].snapshot)

        synchronizeSnapshot(for: selectedDate)
        updateSelectionState()
        focusedOverflowIndex = overflowTasks.indices.last
        updateSummary()
        return true
    }

    @discardableResult
    func promoteSelectionUp() -> Bool {
        if let index = focusedInboxIndex {
            return moveInboxTaskToOverflow(at: index)
        }
        if let index = focusedOverflowIndex {
            return promoteOverflowTaskToFocus(at: index)
        }
        return false
    }

    @discardableResult
    func demoteSelectionDown() -> Bool {
        if focusedTaskID != nil {
            return demoteFocusedTaskToOverflow()
        }
        if let index = focusedOverflowIndex {
            return moveOverflowTaskToInbox(at: index)
        }
        return false
    }

    @discardableResult
    func promotePriorityTaskToFocus() -> Bool {
        if let index = focusedOverflowIndex {
            return promoteOverflowTaskToFocus(at: index)
        }
        if let index = focusedInboxIndex {
            return moveInboxTaskToFocus(at: index)
        }

        if let overflowIndex = overflowTasks.firstIndex(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return promoteOverflowTaskToFocus(at: overflowIndex)
        }

        if let inboxIndex = inboxTasks.firstIndex(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return moveInboxTaskToFocus(at: inboxIndex)
        }

        return false
    }

    @discardableResult
    func markTopIncompleteTaskDone() -> Bool {
        guard let dayIndex = indexOfDay(selectedDate) else { return false }
        if let task = dayEntries[dayIndex].snapshot.tasks.first(where: { !$0.done }) {
            toggleTaskCompletion(on: selectedDate, taskID: task.id)
            return true
        }
        return false
    }

    @discardableResult
    func moveTask(from sourceDate: Date, to targetDate: Date, taskID: FocusTask.ID) -> Bool {
        guard calendar.compare(targetDate, to: sourceDate, toGranularity: .day) == .orderedDescending else { return false }
        guard let sourceIndex = indexOfDay(sourceDate),
              let targetIndex = indexOfDay(targetDate),
              let taskIndex = dayEntries[sourceIndex].snapshot.tasks.firstIndex(where: { $0.id == taskID }) else { return false }

        let task = dayEntries[sourceIndex].snapshot.tasks[taskIndex]
        guard let (updatedSource, updatedTarget) = weekManager.moveTask(dayFrom: sourceDate, dayTo: targetDate, taskIndex: taskIndex) else {
            return false
        }

        dayEntries[sourceIndex].snapshot = updatedSource
        dayEntries[targetIndex].snapshot = updatedTarget

        onTaskMoved?(task, sourceDate, targetDate)
        updateSelectionState()
        updateSummary()
        return true
    }

    func triggerWindDownPrompt() {
        selectedDate = currentDay
        updateSelectionState()
        withAnimation { isWindDownPromptVisible = true }
    }

    func dismissWindDownPrompt() {
        withAnimation { isWindDownPromptVisible = false }
    }

    func logMood(_ mood: Int) {
        let today = currentDay
        guard let index = indexOfDay(today) else { return }
        dayEntries[index].snapshot.mood = mood
        weekManager.save(snapshot: dayEntries[index].snapshot)
        onMoodLogged?(mood, today)
        updateSummary()
        updateSelectionState()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            withAnimation(.easeInOut(duration: 0.25)) {
                self?.isWindDownPromptVisible = false
            }
        }
    }

    func handleDropPayload(_ payload: String, to targetDate: Date) {
        let components = payload.split(separator: "|", maxSplits: 1).map(String.init)
        guard components.count == 2,
              let sourceDate = isoFormatter.date(from: components[0]) else { return }
        _ = moveTask(from: sourceDate, to: targetDate, taskID: components[1])
    }

    func dragPayload(for date: Date, taskID: FocusTask.ID) -> String {
        "\(isoFormatter.string(from: date))|\(taskID)"
    }

    func refreshForCurrentDay() {
        let today = Self.startOfDay(for: Date())
        if today != currentDay {
            currentDay = today
            ensureCurrentWeekLoaded()
        } else {
            loadWeek(containing: today)
        }
    }

    // MARK: - Private

    private func ensureCurrentWeekLoaded() {
        loadWeek(containing: currentDay)
    }

    private func loadWeek(containing date: Date) {
        let bounds = Self.weekBounds(containing: date)
        let snapshots = weekManager.fetchDays(startDate: bounds.start, endDate: bounds.end)
        dayEntries = snapshots.compactMap { snapshot in
            guard let day = isoFormatter.date(from: snapshot.date) else { return nil }
            return DayEntry(date: day, snapshot: snapshot)
        }.sorted { $0.date < $1.date }

        if let index = indexOfDay(selectedDate) {
            selectedDate = dayEntries[index].date
        } else if let todayIndex = indexOfDay(currentDay) {
            selectedDate = dayEntries[todayIndex].date
        } else if let first = dayEntries.first {
            selectedDate = first.date
        }

        updateSelectionState()
        updateSummary()
    }

    private func updateSelectionState() {
        selectedDayMood = mood(for: selectedDate)
        let tasks = tasks(for: selectedDate)
        allTasksCompleted = !tasks.isEmpty && tasks.allSatisfy { $0.done }

        if let index = indexOfDay(selectedDate) {
            overflowTasks = dayEntries[index].snapshot.overflow
            isOverflowCollapsed = dayEntries[index].snapshot.uiState.isOverflowCollapsed
        } else {
            overflowTasks = []
            isOverflowCollapsed = true
        }

        if let currentIndex = focusedOverflowIndex, !overflowTasks.indices.contains(currentIndex) {
            focusedOverflowIndex = nil
        }

        let inboxState = inboxManager.state()
        inboxTasks = inboxState.tasks
        isInboxCollapsed = inboxState.isCollapsed
        if let currentIndex = focusedInboxIndex, !inboxTasks.indices.contains(currentIndex) {
            focusedInboxIndex = nil
        }
    }

    private func updateSummary() {
        weekSummary = weekManager.summaryStats()
    }

    private func indexOfDay(_ date: Date) -> Int? {
        dayEntries.firstIndex { entry in
            calendar.isDate(entry.date, inSameDayAs: date)
        }
    }

    private func scheduleMidnightRefresh() {
        midnightTimer?.invalidate()

        let nextMidnight = Calendar.current.nextDate(after: Date(), matching: DateComponents(hour: 0, minute: 0, second: 5), matchingPolicy: .strict, direction: .forward) ?? Date().addingTimeInterval(86400)
        let interval = max(60, nextMidnight.timeIntervalSinceNow)

        midnightTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.refreshForCurrentDay()
                self?.scheduleMidnightRefresh()
            }
        }
    }

    private static func startOfDay(for date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private static func weekBounds(containing date: Date) -> (start: Date, end: Date) {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone.current
        let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) ?? date
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? date
        return (calendar.startOfDay(for: start), calendar.startOfDay(for: end))
    }

    private func synchronizeSnapshot(for date: Date) {
        let snapshot = weekManager.snapshot(for: date)
        if let index = indexOfDay(date) {
            dayEntries[index].snapshot = snapshot
        }
    }
}
