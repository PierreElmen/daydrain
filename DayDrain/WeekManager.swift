import Foundation

final class WeekManager {
    private let fileManager = FileManager.default
    private let baseDirectory: URL
    private let daysDirectory: URL
    private let todayAliasURL: URL

    private lazy var isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private lazy var isoCalendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone.current
        return calendar
    }()

    private var cachedSnapshots: [String: DailyFocusSnapshot] = [:]

    init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        baseDirectory = base.appendingPathComponent("DayDrain", isDirectory: true)
        daysDirectory = baseDirectory.appendingPathComponent("days", isDirectory: true)
        todayAliasURL = baseDirectory.appendingPathComponent("today.json", isDirectory: false)
        ensureDirectories()
    }

    func fetchDays(startDate: Date, endDate: Date) -> [DailyFocusSnapshot] {
        cachedSnapshots.removeAll()
        var snapshots: [DailyFocusSnapshot] = []
        var current = startOfDay(for: startDate)
        let limit = startOfDay(for: endDate)

        while current <= limit {
            let snapshot = loadSnapshot(for: current)
            cachedSnapshots[snapshot.date] = snapshot
            snapshots.append(snapshot)
            guard let next = isoCalendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }

        return snapshots.sorted { $0.date < $1.date }
    }

    func save(snapshot: DailyFocusSnapshot) {
        let sanitized = sanitizedSnapshot(snapshot)
        cachedSnapshots[sanitized.date] = sanitized
        persist(snapshot: sanitized)
    }

    func snapshot(for date: Date) -> DailyFocusSnapshot {
        let key = isoFormatter.string(from: startOfDay(for: date))
        if let cached = cachedSnapshots[key] {
            return cached
        }
        let snapshot = loadSnapshot(for: date)
        cachedSnapshots[key] = snapshot
        return snapshot
    }

    func moveTask(dayFrom: Date, dayTo: Date, taskIndex: Int) -> (DailyFocusSnapshot, DailyFocusSnapshot)? {
        let fromKey = isoFormatter.string(from: startOfDay(for: dayFrom))
        let toKey = isoFormatter.string(from: startOfDay(for: dayTo))

        var fromSnapshot = cachedSnapshots[fromKey] ?? loadSnapshot(for: dayFrom)
        var toSnapshot = cachedSnapshots[toKey] ?? loadSnapshot(for: dayTo)

        guard taskIndex < fromSnapshot.tasks.count else { return nil }

        let task = fromSnapshot.tasks[taskIndex]
        let trimmed = task.text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty, !task.done else { return nil }

        let destinationIndex = preferredDestinationIndex(for: toSnapshot.tasks)
        toSnapshot.tasks[destinationIndex].text = String(trimmed.prefix(80))
        toSnapshot.tasks[destinationIndex].note = String(task.note.prefix(200))
        toSnapshot.tasks[destinationIndex].done = false

        fromSnapshot.tasks[taskIndex].text = ""
        fromSnapshot.tasks[taskIndex].note = ""
        fromSnapshot.tasks[taskIndex].done = false

        save(snapshot: fromSnapshot)
        save(snapshot: toSnapshot)

        return (fromSnapshot, toSnapshot)
    }

    func summaryStats() -> WeekSummary {
        let sortedSnapshots = cachedSnapshots.values.sorted { $0.date < $1.date }
        let completed = sortedSnapshots.reduce(into: 0) { partial, snapshot in
            partial += snapshot.tasks.filter { $0.done }.count
        }
        let total = sortedSnapshots.reduce(into: 0) { partial, snapshot in
            partial += snapshot.tasks.count
        }
        let moods = sortedSnapshots.compactMap { $0.mood }
        let averageMood = moods.isEmpty ? nil : Double(moods.reduce(0, +)) / Double(moods.count)
        let breakdown: [WeekSummary.DayBreakdown] = sortedSnapshots.compactMap { snapshot in
            guard let date = isoFormatter.date(from: snapshot.date) else { return nil }
            let completedCount = snapshot.tasks.filter { $0.done }.count
            return WeekSummary.DayBreakdown(date: date, completed: completedCount, total: snapshot.tasks.count, mood: snapshot.mood)
        }
        return WeekSummary(completed: completed, total: total, averageMood: averageMood, dayBreakdown: breakdown)
    }

    // MARK: - Helpers

    private func ensureDirectories() {
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }
        if !fileManager.fileExists(atPath: daysDirectory.path) {
            try? fileManager.createDirectory(at: daysDirectory, withIntermediateDirectories: true)
        }
    }

    private func loadSnapshot(for date: Date) -> DailyFocusSnapshot {
        let key = isoFormatter.string(from: startOfDay(for: date))
        let url = fileURL(for: key)

        if let data = try? Data(contentsOf: url),
           let snapshot = try? JSONDecoder().decode(DailyFocusSnapshot.self, from: data) {
            return sanitizedSnapshot(snapshot)
        }

        if let aliasData = try? Data(contentsOf: todayAliasURL),
           let aliasSnapshot = try? JSONDecoder().decode(DailyFocusSnapshot.self, from: aliasData),
           aliasSnapshot.date == key {
            let sanitized = sanitizedSnapshot(aliasSnapshot)
            persist(snapshot: sanitized, at: url)
            return sanitized
        }

        let newSnapshot = makeSnapshot(for: date)
        persist(snapshot: newSnapshot, at: url)
        return newSnapshot
    }

    private func makeSnapshot(for date: Date) -> DailyFocusSnapshot {
        var tasks = Self.defaultTasks()
        let previousDate = isoCalendar.date(byAdding: .day, value: -1, to: date)

        if let previousDate,
           let previousData = try? Data(contentsOf: fileURL(for: isoFormatter.string(from: previousDate))),
           let previousSnapshot = try? JSONDecoder().decode(DailyFocusSnapshot.self, from: previousData) {
            var slotIndex = 0
            for task in previousSnapshot.tasks where !task.done {
                let trimmed = task.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, slotIndex < tasks.count else { continue }
                tasks[slotIndex].text = String(trimmed.prefix(80))
                tasks[slotIndex].note = String(task.note.prefix(200))
                tasks[slotIndex].done = false
                slotIndex += 1
            }
        }

        let iso = isoFormatter.string(from: startOfDay(for: date))
        return DailyFocusSnapshot(date: iso, tasks: tasks, mood: nil, overflow: [], inbox: nil, uiState: DailyUIState())
    }

    private func sanitizedSnapshot(_ snapshot: DailyFocusSnapshot) -> DailyFocusSnapshot {
        var sanitizedTasks = Self.defaultTasks()
        for index in sanitizedTasks.indices {
            if let match = snapshot.tasks.first(where: { $0.id == sanitizedTasks[index].id }) {
                sanitizedTasks[index].text = String(match.text.prefix(80))
                sanitizedTasks[index].done = match.done
                sanitizedTasks[index].note = String(match.note.prefix(200))
            }
        }

        let sanitizedOverflow = snapshot.overflow.map { $0.sanitized() }
        let sanitizedInbox = snapshot.inbox?.map { $0.sanitized() }
        let sanitizedUIState = snapshot.uiState.sanitized()

        return DailyFocusSnapshot(date: snapshot.date,
                                  tasks: sanitizedTasks,
                                  mood: snapshot.mood,
                                  overflow: sanitizedOverflow,
                                  inbox: sanitizedInbox,
                                  uiState: sanitizedUIState)
    }

    private func persist(snapshot: DailyFocusSnapshot, at url: URL? = nil) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        let destinationURL = url ?? fileURL(for: snapshot.date)
        try? data.write(to: destinationURL, options: .atomic)

        if isToday(snapshot.date) {
            try? data.write(to: todayAliasURL, options: .atomic)
        }
    }

    private func fileURL(for dateString: String) -> URL {
        daysDirectory.appendingPathComponent("\(dateString).json", isDirectory: false)
    }

    private func startOfDay(for date: Date) -> Date {
        isoCalendar.startOfDay(for: date)
    }

    private func isToday(_ dateString: String) -> Bool {
        guard let date = isoFormatter.date(from: dateString) else { return false }
        return isoCalendar.isDateInToday(date)
    }

    private func preferredDestinationIndex(for tasks: [FocusTask]) -> Int {
        if let emptyIndex = tasks.firstIndex(where: { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return emptyIndex
        }
        if let undoneIndex = tasks.firstIndex(where: { !$0.done }) {
            return undoneIndex
        }
        return max(0, tasks.count - 1)
    }

    private static func defaultTasks() -> [FocusTask] {
        [
            FocusTask(label: "Focus 1", text: "", done: false, note: ""),
            FocusTask(label: "Focus 2", text: "", done: false, note: ""),
            FocusTask(label: "Focus 3", text: "", done: false, note: "")
        ]
    }
}
