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

    enum PanelContext: Equatable {
        case focus(FocusTask.ID)
        case overflow(UUID)
        case inbox(UUID)
    }

    enum PanelSection: String, Codable {
        case focus
        case overflow
        case inbox
    }

    private struct DragTransferPayload: Codable {
        let date: String
        let id: String
        let section: PanelSection
    }

    @Published private(set) var dayEntries: [DayEntry]
    @Published private(set) var selectedDate: Date
    @Published private(set) var selectedDayMood: Int?
    @Published private(set) var weekSummary: WeekSummary
    @Published private(set) var pulseToken: Int
    @Published private(set) var allTasksCompleted: Bool
    @Published private(set) var overflowTasks: [OverflowTask]
    @Published private(set) var inboxItems: [InboxItem]
    @Published var focusedTaskID: FocusTask.ID?
    @Published var isWindDownPromptVisible: Bool
    @Published var isOverflowCollapsed: Bool
    @Published var isInboxExpanded: Bool
    @Published var activeContext: PanelContext?
    @Published var pendingInboxPromotion: InboxItem?

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
    private var midnightTimer: Timer?
    private var currentDay: Date
    private var calendar = Calendar.current
    private let overflowManager = OverflowManager()
    private let inboxManager = InboxManager()
    private let defaults = UserDefaults.standard

    private static let overflowCollapsedKey = "DayDrainOverflowCollapsed"
    private static let inboxExpandedKey = "DayDrainInboxExpanded"

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
        self.currentDay = Self.startOfDay(for: Date())
        self.selectedDate = currentDay
        self.weekSummary = .empty
        self.pulseToken = 0
        self.allTasksCompleted = false
        self.dayEntries = []
        self.overflowTasks = []
        self.inboxItems = []
        self.isWindDownPromptVisible = false
        self.selectedDayMood = nil
        self.isOverflowCollapsed = defaults.object(forKey: Self.overflowCollapsedKey) as? Bool ?? true
        self.isInboxExpanded = defaults.object(forKey: Self.inboxExpandedKey) as? Bool ?? false
        self.activeContext = nil
        self.pendingInboxPromotion = nil

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
        updateSelectionState()
    }

    func goToPreviousDay() {
        guard let currentIndex = indexOfDay(selectedDate), currentIndex > 0 else { return }
        selectedDate = dayEntries[currentIndex - 1].date
        focusedTaskID = nil
        updateSelectionState()
    }

    func goToNextDay() {
        guard let currentIndex = indexOfDay(selectedDate), currentIndex < dayEntries.count - 1 else { return }
        selectedDate = dayEntries[currentIndex + 1].date
        focusedTaskID = nil
        updateSelectionState()
    }

    func tasks(for date: Date) -> [FocusTask] {
        guard let index = indexOfDay(date) else { return [] }
        return dayEntries[index].snapshot.tasks
    }

    func overflowTasks(for date: Date) -> [OverflowTask] {
        guard let index = indexOfDay(date) else { return [] }
        return dayEntries[index].snapshot.overflow
    }

    func inboxItems(for date: Date) -> [InboxItem] {
        guard let index = indexOfDay(date) else { return [] }
        return dayEntries[index].snapshot.inbox
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

    @discardableResult
    func markTopIncompleteTaskDone() -> Bool {
        guard let dayIndex = indexOfDay(selectedDate) else { return false }
        if let task = dayEntries[dayIndex].snapshot.tasks.first(where: { !$0.done }) {
            toggleTaskCompletion(on: selectedDate, taskID: task.id)
            return true
        }
        return false
    }

    func toggleOverflowSection() {
        isOverflowCollapsed.toggle()
        defaults.set(isOverflowCollapsed, forKey: Self.overflowCollapsedKey)
    }

    func showInboxPanel() {
        if !isInboxExpanded {
            isInboxExpanded = true
            defaults.set(true, forKey: Self.inboxExpandedKey)
        }
    }

    func hideInboxPanel() {
        if isInboxExpanded {
            isInboxExpanded = false
            defaults.set(false, forKey: Self.inboxExpandedKey)
        }
    }

    func toggleInboxPanel() {
        isInboxExpanded.toggle()
        defaults.set(isInboxExpanded, forKey: Self.inboxExpandedKey)
    }

    @discardableResult
    func addOverflowTask(text: String) -> Bool {
        guard var entry = entry(for: selectedDate) else { return false }
        guard let task = overflowManager.addTask(text: text, to: &entry.snapshot) else { return false }
        update(entry: entry)
        overflowTasks = entry.snapshot.overflow
        activeContext = .overflow(task.id)
        return true
    }

    func updateOverflowTask(id: UUID, text: String) {
        guard var entry = entry(for: selectedDate) else { return }
        overflowManager.updateTask(id: id, text: text, in: &entry.snapshot)
        update(entry: entry)
        overflowTasks = entry.snapshot.overflow
    }

    func toggleOverflowTask(id: UUID) {
        guard var entry = entry(for: selectedDate) else { return }
        overflowManager.toggleTask(id: id, in: &entry.snapshot)
        update(entry: entry)
        overflowTasks = entry.snapshot.overflow
    }

    func removeOverflowTask(id: UUID) {
        guard var entry = entry(for: selectedDate) else { return }
        _ = overflowManager.removeTask(id: id, from: &entry.snapshot)
        update(entry: entry)
        overflowTasks = entry.snapshot.overflow
    }

    @discardableResult
    func addInboxItem(text: String, priority: InboxPriority) -> Bool {
        var items = inboxItems
        guard let item = inboxManager.addItem(text: text, priority: priority, to: &items) else { return false }
        persistInbox(items)
        inboxItems = items
        activeContext = .inbox(item.id)
        return true
    }

    func updateInboxItem(id: UUID, text: String) {
        var items = inboxItems
        inboxManager.updateText(for: id, text: text, in: &items)
        persistInbox(items)
        inboxItems = items
    }

    func updateInboxPriority(id: UUID, priority: InboxPriority) {
        var items = inboxItems
        inboxManager.updatePriority(for: id, priority: priority, in: &items)
        persistInbox(items)
        inboxItems = items
    }

    func toggleInboxItem(id: UUID) {
        var items = inboxItems
        inboxManager.toggleDone(for: id, in: &items)
        persistInbox(items)
        inboxItems = items
    }

    func removeInboxItem(id: UUID) {
        var items = inboxItems
        _ = inboxManager.remove(id: id, from: &items)
        persistInbox(items)
        inboxItems = items
    }

    enum InboxPromotionOutcome {
        case success
        case requiresReplacement(InboxItem)
        case failed
    }

    func attemptPromoteInboxItem(_ id: UUID) -> InboxPromotionOutcome {
        guard var entry = entry(for: selectedDate) else { return .failed }
        guard let inboxIndex = inboxItems.firstIndex(where: { $0.id == id }) else { return .failed }
        let item = inboxItems[inboxIndex]
        let trimmed = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failed }

        if let slot = entry.snapshot.tasks.firstIndex(where: { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            entry.snapshot.tasks[slot].text = String(trimmed.prefix(80))
            entry.snapshot.tasks[slot].note = ""
            entry.snapshot.tasks[slot].done = false
            update(entry: entry)
            removeInboxItem(id: id)
            focusedTaskID = entry.snapshot.tasks[slot].id
            updateSummary()
            updateSelectionState()
            return .success
        }

        pendingInboxPromotion = item
        return .requiresReplacement(item)
    }

    func replaceFocus(with label: String, using itemID: UUID) -> Bool {
        guard var entry = entry(for: selectedDate) else { return false }
        guard let focusIndex = entry.snapshot.tasks.firstIndex(where: { $0.label == label }) else { return false }
        guard let item = inboxItems.first(where: { $0.id == itemID }) else { return false }

        entry.snapshot.tasks[focusIndex].text = String(item.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        entry.snapshot.tasks[focusIndex].note = ""
        entry.snapshot.tasks[focusIndex].done = false
        update(entry: entry)
        removeInboxItem(id: itemID)
        focusedTaskID = entry.snapshot.tasks[focusIndex].id
        updateSummary()
        pendingInboxPromotion = nil
        updateSelectionState()
        return true
    }

    func cancelPromotionRequest() {
        pendingInboxPromotion = nil
    }

    func moveInboxToOverflow(_ id: UUID) {
        guard var entry = entry(for: selectedDate) else { return }
        var items = inboxItems
        guard let item = inboxManager.moveToOverflow(id: id, from: &items) else { return }
        persistInbox(items)
        inboxItems = items
        if let task = overflowManager.addTask(text: item.text, to: &entry.snapshot) {
            update(entry: entry)
            overflowTasks = entry.snapshot.overflow
            activeContext = .overflow(task.id)
        }
    }

    func moveOverflowToInbox(_ id: UUID, priority: InboxPriority) {
        guard var entry = entry(for: selectedDate) else { return }
        guard let task = overflowManager.moveToInbox(id: id, from: &entry.snapshot) else { return }
        update(entry: entry)
        overflowTasks = entry.snapshot.overflow

        var items = inboxItems
        if let newItem = inboxManager.addItem(text: task.text, priority: priority, to: &items) {
            persistInbox(items)
            inboxItems = items
            activeContext = .inbox(newItem.id)
        }
    }

    func moveFocusTaskToOverflow(_ id: FocusTask.ID) {
        guard var entry = entry(for: selectedDate) else { return }
        guard let focusIndex = entry.snapshot.tasks.firstIndex(where: { $0.id == id }) else { return }
        let focusTask = entry.snapshot.tasks[focusIndex]
        guard let task = overflowManager.moveFromFocus(task: focusTask, into: &entry.snapshot) else { return }
        entry.snapshot.tasks[focusIndex].text = ""
        entry.snapshot.tasks[focusIndex].note = ""
        entry.snapshot.tasks[focusIndex].done = false
        update(entry: entry)
        overflowTasks = entry.snapshot.overflow
        focusedTaskID = nil
        activeContext = .overflow(task.id)
        updateSummary()
        updateSelectionState()
    }

    func moveFocusTaskToInbox(_ id: FocusTask.ID, priority: InboxPriority) {
        guard var entry = entry(for: selectedDate) else { return }
        guard let focusIndex = entry.snapshot.tasks.firstIndex(where: { $0.id == id }) else { return }
        let focusTask = entry.snapshot.tasks[focusIndex]
        let trimmed = focusTask.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var items = inboxItems
        if let newItem = inboxManager.addItem(text: trimmed, priority: priority, to: &items) {
            entry.snapshot.tasks[focusIndex].text = ""
            entry.snapshot.tasks[focusIndex].note = ""
            entry.snapshot.tasks[focusIndex].done = false
            update(entry: entry)
            persistInbox(items)
            inboxItems = items
            overflowTasks = entry.snapshot.overflow
            focusedTaskID = nil
            activeContext = .inbox(newItem.id)
            updateSummary()
            updateSelectionState()
        }
    }

    func setActiveContext(_ context: PanelContext?) {
        activeContext = context
    }

    func moveActiveContextTowardFocus(defaultPriority: InboxPriority) {
        guard let context = activeContext else { return }
        switch context {
        case .inbox(let id):
            let outcome = attemptPromoteInboxItem(id)
            if case .requiresReplacement = outcome {
                // leave pending for UI to handle
            }
        case .overflow(let id):
            moveOverflowToFocus(id: id)
        case .focus:
            break
        }
    }

    func moveActiveContextAwayFromFocus(defaultPriority: InboxPriority) {
        guard let context = activeContext else { return }
        switch context {
        case .focus(let id):
            moveFocusTaskToOverflow(id)
        case .overflow(let id):
            moveOverflowToInbox(id, priority: defaultPriority)
        case .inbox:
            break
        }
    }

    private func moveOverflowToFocus(id: UUID) {
        guard var entry = entry(for: selectedDate) else { return }
        guard let overflowIndex = entry.snapshot.overflow.firstIndex(where: { $0.id == id }) else { return }
        let task = entry.snapshot.overflow[overflowIndex]
        let trimmed = task.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let slot = entry.snapshot.tasks.firstIndex(where: { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            entry.snapshot.tasks[slot].text = String(trimmed.prefix(80))
            entry.snapshot.tasks[slot].note = ""
            entry.snapshot.tasks[slot].done = false
            entry.snapshot.overflow.remove(at: overflowIndex)
            update(entry: entry)
            overflowTasks = entry.snapshot.overflow
            focusedTaskID = entry.snapshot.tasks[slot].id
            activeContext = .focus(entry.snapshot.tasks[slot].id)
            updateSummary()
            updateSelectionState()
        }
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

    func handleDropPayload(_ payload: String, to targetSection: PanelSection, on targetDate: Date) {
        if let data = payload.data(using: .utf8),
           let transfer = try? JSONDecoder().decode(DragTransferPayload.self, from: data),
           let sourceDate = isoFormatter.date(from: transfer.date) {
            handleTransfer(transfer, from: sourceDate, to: targetSection, on: targetDate)
            return
        }

        let components = payload.split(separator: "|", maxSplits: 1).map(String.init)
        guard components.count == 2,
              let sourceDate = isoFormatter.date(from: components[0]) else { return }
        _ = moveTask(from: sourceDate, to: targetDate, taskID: components[1])
    }

    func dragPayload(for section: PanelSection, date: Date, id: String) -> String {
        let payload = DragTransferPayload(date: isoFormatter.string(from: date), id: id, section: section)
        if let data = try? JSONEncoder().encode(payload),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return ""
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

    private func entry(for date: Date) -> DayEntry? {
        guard let index = indexOfDay(date) else { return nil }
        return dayEntries[index]
    }

    private func update(entry: DayEntry) {
        guard let index = indexOfDay(entry.date) else { return }
        dayEntries[index] = entry
        weekManager.save(snapshot: entry.snapshot)
        if calendar.isDate(entry.date, inSameDayAs: selectedDate) {
            overflowTasks = entry.snapshot.overflow
        }
    }

    private func persistInbox(_ items: [InboxItem]) {
        for index in dayEntries.indices {
            dayEntries[index].snapshot.inbox = items
            weekManager.save(snapshot: dayEntries[index].snapshot)
        }
    }

    private func handleTransfer(_ transfer: DragTransferPayload, from sourceDate: Date, to targetSection: PanelSection, on targetDate: Date) {
        switch transfer.section {
        case .focus:
            handleFocusTransfer(id: transfer.id, from: sourceDate, to: targetSection, on: targetDate)
        case .overflow:
            handleOverflowTransfer(idString: transfer.id, from: sourceDate, to: targetSection, on: targetDate)
        case .inbox:
            handleInboxTransfer(idString: transfer.id, from: sourceDate, to: targetSection, on: targetDate)
        }
    }

    private func handleFocusTransfer(id: String, from sourceDate: Date, to targetSection: PanelSection, on targetDate: Date) {
        switch targetSection {
        case .focus:
            _ = moveTask(from: sourceDate, to: targetDate, taskID: id)
        case .overflow:
            guard calendar.isDate(sourceDate, inSameDayAs: targetDate) else { return }
            moveFocusTaskToOverflow(id)
        case .inbox:
            guard calendar.isDate(sourceDate, inSameDayAs: targetDate) else { return }
            moveFocusTaskToInbox(id, priority: .medium)
        }
    }

    private func handleOverflowTransfer(idString: String, from sourceDate: Date, to targetSection: PanelSection, on targetDate: Date) {
        guard calendar.isDate(sourceDate, inSameDayAs: targetDate) else { return }
        guard let id = UUID(uuidString: idString) else { return }
        switch targetSection {
        case .focus:
            moveOverflowToFocus(id: id)
        case .overflow:
            break
        case .inbox:
            moveOverflowToInbox(id, priority: .medium)
        }
    }

    private func handleInboxTransfer(idString: String, from sourceDate: Date, to targetSection: PanelSection, on targetDate: Date) {
        guard calendar.isDate(sourceDate, inSameDayAs: targetDate) else { return }
        guard let id = UUID(uuidString: idString) else { return }
        switch targetSection {
        case .focus:
            let outcome = attemptPromoteInboxItem(id)
            if case .requiresReplacement(let item) = outcome {
                pendingInboxPromotion = item
            }
        case .overflow:
            moveInboxToOverflow(id)
        case .inbox:
            break
        }
    }

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
        overflowTasks = overflowTasks(for: selectedDate)
        inboxItems = inboxItems(for: selectedDate)
        let tasks = tasks(for: selectedDate)
        allTasksCompleted = !tasks.isEmpty && tasks.allSatisfy { $0.done }
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
}
