import Foundation
import Combine

struct FocusTask: Identifiable, Codable, Equatable {
    let label: String
    var text: String
    var done: Bool
    var note: String

    var id: String { label }
}

struct DailyFocusSnapshot: Codable {
    var date: String
    var tasks: [FocusTask]
}

@MainActor
final class ToDoManager: ObservableObject {
    @Published private(set) var tasks: [FocusTask]
    @Published private(set) var pulseToken: Int = 0
    @Published private(set) var allTasksCompleted: Bool = false
    @Published var focusedTaskID: FocusTask.ID?

    private let fileManager = FileManager.default
    private let directoryURL: URL
    private let todayURL: URL
    private let yesterdayURL: URL
    private let tomorrowURL: URL
    private var midnightTimer: Timer?
    private var currentDay: Date

    private lazy var isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    init() {
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directoryURL = directory.appendingPathComponent("DayDrain", isDirectory: true)
        todayURL = directoryURL.appendingPathComponent("today.json", isDirectory: false)
        yesterdayURL = directoryURL.appendingPathComponent("yesterday.json", isDirectory: false)
        tomorrowURL = directoryURL.appendingPathComponent("tomorrow.json", isDirectory: false)

        tasks = Self.defaultTasks()
        currentDay = Self.startOfDay(for: Date())

        ensureStorageDirectoryExists()
        refreshForCurrentDay()
        scheduleMidnightRefresh()
    }

    deinit {
        midnightTimer?.invalidate()
    }

    var tooltip: String { "Tackle the hardest one first." }

    var highlightedTaskID: FocusTask.ID? {
        tasks.first(where: { !$0.done })?.id
            ?? tasks.first?.id
    }

    func toggleTaskCompletion(for taskID: FocusTask.ID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].done.toggle()
        if tasks[index].done {
            triggerPulse()
        }
        updateCompletionState()
        persistToday()
    }

    func updateTaskText(for taskID: FocusTask.ID, text: String) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let trimmed = String(text.prefix(80))
        tasks[index].text = trimmed
        if trimmed.isEmpty {
            tasks[index].done = false
        }
        updateCompletionState()
        persistToday()
    }

    func clearTask(_ taskID: FocusTask.ID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].text = ""
        tasks[index].note = ""
        tasks[index].done = false
        updateCompletionState()
        persistToday()
    }

    @discardableResult
    func quickAddTask() -> Bool {
        if let index = tasks.firstIndex(where: { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            tasks[index].done = false
            updateCompletionState()
            focusedTaskID = tasks[index].id
            persistToday()
            return true
        }
        return false
    }

    @discardableResult
    func markTopIncompleteTaskDone() -> Bool {
        guard let task = tasks.first(where: { !$0.done }) else { return false }
        toggleTaskCompletion(for: task.id)
        return true
    }

    func refreshForCurrentDay() {
        let today = Self.startOfDay(for: Date())
        currentDay = today

        let todayString = isoFormatter.string(from: today)
        let yesterday = Self.adjustDay(today, by: -1)
        let yesterdayString = isoFormatter.string(from: yesterday)
        let tomorrow = Self.adjustDay(today, by: 1)
        let tomorrowString = isoFormatter.string(from: tomorrow)

        ensureStorageDirectoryExists()

        var previousDaySnapshot: DailyFocusSnapshot?
        if let storedYesterday = loadSnapshot(from: yesterdayURL), storedYesterday.date == yesterdayString {
            previousDaySnapshot = storedYesterday
        }

        if previousDaySnapshot == nil,
           let staleToday = loadSnapshot(from: todayURL), staleToday.date == yesterdayString {
            previousDaySnapshot = staleToday
            save(snapshot: staleToday, to: yesterdayURL)
        }

        if let staleToday = loadSnapshot(from: todayURL), staleToday.date != todayString {
            if let staleDate = isoFormatter.date(from: staleToday.date), staleDate < today {
                save(snapshot: staleToday, to: yesterdayURL)
            } else if let staleDate = isoFormatter.date(from: staleToday.date), staleDate > today {
                save(snapshot: staleToday, to: tomorrowURL)
            }
        }

        if let existingToday = loadSnapshot(from: todayURL), existingToday.date == todayString {
            tasks = sanitizedTasks(existingToday.tasks)
            updateCompletionState()
        } else if let prefill = loadSnapshot(from: tomorrowURL), prefill.date == todayString {
            var sanitized = sanitizedTasks(prefill.tasks)
            for index in sanitized.indices {
                sanitized[index].done = false
            }
            tasks = sanitized
            updateCompletionState()
            save(snapshot: DailyFocusSnapshot(date: tomorrowString, tasks: Self.defaultTasks()), to: tomorrowURL)
            persistToday()
        } else {
            var newTasks = Self.defaultTasks()
            if let carryOver = previousDaySnapshot {
                var slotIndex = 0
                for task in carryOver.tasks where !task.done {
                    let trimmed = task.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, slotIndex < newTasks.count else { continue }
                    newTasks[slotIndex].text = String(trimmed.prefix(80))
                    newTasks[slotIndex].note = task.note
                    newTasks[slotIndex].done = false
                    slotIndex += 1
                }
            }
            tasks = newTasks
            updateCompletionState()
            persistToday()
        }

        if let snapshot = previousDaySnapshot {
            save(snapshot: snapshot, to: yesterdayURL)
        } else {
            save(snapshot: DailyFocusSnapshot(date: yesterdayString, tasks: Self.defaultTasks()), to: yesterdayURL)
        }

        if let tomorrowSnapshot = loadSnapshot(from: tomorrowURL), tomorrowSnapshot.date == tomorrowString {
            // keep user-provided placeholder
        } else {
            save(snapshot: DailyFocusSnapshot(date: tomorrowString, tasks: Self.defaultTasks()), to: tomorrowURL)
        }
    }

    private func ensureStorageDirectoryExists() {
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
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

    private func triggerPulse() {
        pulseToken += 1
    }

    private func updateCompletionState() {
        allTasksCompleted = tasks.allSatisfy { $0.done }
    }

    private func persistToday() {
        let snapshot = DailyFocusSnapshot(date: isoFormatter.string(from: currentDay), tasks: tasks)
        save(snapshot: snapshot, to: todayURL)
    }

    private func save(snapshot: DailyFocusSnapshot, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func loadSnapshot(from url: URL) -> DailyFocusSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DailyFocusSnapshot.self, from: data)
    }

    private func sanitizedTasks(_ tasks: [FocusTask]) -> [FocusTask] {
        var sanitized = Self.defaultTasks()
        for index in sanitized.indices {
            if let match = tasks.first(where: { $0.id == sanitized[index].id }) {
                sanitized[index].text = String(match.text.prefix(80))
                sanitized[index].done = match.done
                sanitized[index].note = match.note
            }
        }
        return sanitized
    }

    private static func startOfDay(for date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private static func adjustDay(_ date: Date, by days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: date) ?? date
    }

    private static func defaultTasks() -> [FocusTask] {
        [
            FocusTask(label: "Focus 1", text: "", done: false, note: ""),
            FocusTask(label: "Focus 2", text: "", done: false, note: ""),
            FocusTask(label: "Focus 3", text: "", done: false, note: "")
        ]
    }
}
