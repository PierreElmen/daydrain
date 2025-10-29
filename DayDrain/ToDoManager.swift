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
    @Published var focusedTaskID: FocusTask.ID?
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
        self.currentDay = Self.startOfDay(for: Date())
        self.selectedDate = currentDay
        self.weekSummary = .empty
        self.pulseToken = 0
        self.allTasksCompleted = false
        self.dayEntries = []
        self.isWindDownPromptVisible = false
        self.selectedDayMood = nil

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
