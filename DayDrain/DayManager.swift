import SwiftUI
import Combine

struct TimeComponents: Codable, Equatable {
    var hour: Int
    var minute: Int

    func date(on date: Date) -> Date? {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components)
    }

    static func from(date: Date) -> TimeComponents {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return .init(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }
}

/// Represents a configurable slice of the workday.
struct WorkBlock: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var start: TimeComponents
    var end: TimeComponents

    var isValid: Bool {
        start.totalMinutes < end.totalMinutes
    }

    var duration: TimeInterval {
        let minutes = max(0, end.totalMinutes - start.totalMinutes)
        return TimeInterval(minutes * 60)
    }

    func startDate(on date: Date) -> Date? {
        start.date(on: date)
    }

    func endDate(on date: Date) -> Date? {
        end.date(on: date)
    }
}

extension TimeComponents {
    var totalMinutes: Int {
        (hour * 60) + minute
    }
}

/// Represents the user configurable settings that drive the draining bar.
struct WorkdaySettings: Codable {
    var selectedWeekdays: [Int]
    var displayMode: DayDisplayMode.RawValue
    var showMenuValue: Bool = false
    var persistOverflowState: Bool = false
    var workBlocks: [Int: [WorkBlock]] = [:]
    var startTime: TimeComponents? // Legacy support
    var endTime: TimeComponents? // Legacy support

    enum CodingKeys: String, CodingKey {
        case selectedWeekdays
        case startTime
        case endTime
        case displayMode
        case showMenuValue
        case persistOverflowState
        case workBlocks
    }

    init(selectedWeekdays: [Int],
         displayMode: DayDisplayMode.RawValue,
         showMenuValue: Bool,
         persistOverflowState: Bool,
         workBlocks: [Int: [WorkBlock]]) {
        self.selectedWeekdays = selectedWeekdays
        self.displayMode = displayMode
        self.showMenuValue = showMenuValue
        self.persistOverflowState = persistOverflowState
        self.workBlocks = workBlocks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.selectedWeekdays = try container.decodeIfPresent([Int].self, forKey: .selectedWeekdays) ?? []
        self.displayMode = try container.decodeIfPresent(String.self, forKey: .displayMode) ?? DayDisplayMode.percentage.rawValue
        self.showMenuValue = try container.decodeIfPresent(Bool.self, forKey: .showMenuValue) ?? false
        self.persistOverflowState = try container.decodeIfPresent(Bool.self, forKey: .persistOverflowState) ?? false
        self.workBlocks = try container.decodeIfPresent([Int: [WorkBlock]].self, forKey: .workBlocks) ?? [:]
        self.startTime = try container.decodeIfPresent(TimeComponents.self, forKey: .startTime)
        self.endTime = try container.decodeIfPresent(TimeComponents.self, forKey: .endTime)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(selectedWeekdays, forKey: .selectedWeekdays)
        try container.encode(displayMode, forKey: .displayMode)
        try container.encode(showMenuValue, forKey: .showMenuValue)
        try container.encode(persistOverflowState, forKey: .persistOverflowState)
        try container.encode(workBlocks, forKey: .workBlocks)
    }
}

/// Days of the week available for configuration. Calendar weekday values follow the user's locale
/// where Sunday = 1 and Saturday = 7.
enum Weekday: Int, CaseIterable, Identifiable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    var id: Int { rawValue }

    var localizedName: String {
        let symbols = Calendar.current.weekdaySymbols
        let index = (rawValue - 1) % symbols.count
        return symbols[index]
    }
}

/// Preferred presentation of the remaining workday.
enum DayDisplayMode: String, CaseIterable, Identifiable, Codable {
    case percentage
    case hours
    case hoursAndMinutes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .percentage:
            return "Percentage"
        case .hours:
            return "Hours left"
        case .hoursAndMinutes:
            return "Hours & minutes left"
        }
    }
}

/// Central manager that keeps track of the configured schedule, handles persistence and publishes
/// the values required to render the menu bar item.
@MainActor
final class DayManager: ObservableObject {
    @Published var workBlocks: [Weekday: [WorkBlock]]
    @Published var displayMode: DayDisplayMode
    @Published var showMenuValue: Bool
    @Published var persistOverflowState: Bool

    @Published private(set) var progress: Double = 0
    @Published private(set) var isActive: Bool = false
    @Published private(set) var displayText: String = ""
    @Published private(set) var menuValueText: String = ""

    var onDayComplete: (() -> Void)?

    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var hasTriggeredCompletionForCurrentDay = false
    private var lastCompletionDay: DateComponents?

    private let defaults = UserDefaults.standard
    private let settingsKey = "WorkdaySettings"

    init() {
        let defaults = Self.defaultSettings()

        if let data = self.defaults.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(WorkdaySettings.self, from: data) {
            self.displayMode = DayDisplayMode(rawValue: decoded.displayMode) ?? defaults.displayMode
            self.showMenuValue = decoded.showMenuValue
            self.persistOverflowState = decoded.persistOverflowState

            let migratedBlocks = decoded.workBlocks.reduce(into: [Weekday: [WorkBlock]]()) { partialResult, item in
                guard let weekday = Weekday(rawValue: item.key) else { return }
                partialResult[weekday] = item.value
            }

            if !migratedBlocks.isEmpty {
                self.workBlocks = migratedBlocks
            } else if let legacyStart = decoded.startTime, let legacyEnd = decoded.endTime {
                let legacyBlock = WorkBlock(start: legacyStart, end: legacyEnd)
                let weekdays = decoded.selectedWeekdays.compactMap(Weekday.init(rawValue:))
                var legacySchedule: [Weekday: [WorkBlock]] = [:]
                weekdays.forEach { legacySchedule[$0] = [legacyBlock] }
                self.workBlocks = legacySchedule.isEmpty ? defaults.workBlocks : legacySchedule
            } else {
                self.workBlocks = defaults.workBlocks
            }
        } else {
            self.workBlocks = defaults.workBlocks
            self.displayMode = defaults.displayMode
            self.showMenuValue = defaults.showMenuValue
            self.persistOverflowState = defaults.persistOverflowState
        }

        bindSettingsChanges()
        configureTimer()
        refresh()
    }

    deinit {
        timer?.invalidate()
    }

    private static func defaultSettings() -> (workBlocks: [Weekday: [WorkBlock]], displayMode: DayDisplayMode, showMenuValue: Bool, persistOverflowState: Bool) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let defaultStart = calendar.date(byAdding: DateComponents(hour: 9), to: startOfDay) ?? Date()
        let defaultEnd = calendar.date(byAdding: DateComponents(hour: 17), to: startOfDay) ?? Date()
        let defaultBlock = WorkBlock(start: TimeComponents.from(date: defaultStart), end: TimeComponents.from(date: defaultEnd))
        let weekdays: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday]
        var blocks: [Weekday: [WorkBlock]] = [:]
        weekdays.forEach { blocks[$0] = [defaultBlock] }

        return (workBlocks: blocks,
                displayMode: .percentage,
                showMenuValue: false,
                persistOverflowState: false)
    }

    private func bindSettingsChanges() {
        $workBlocks
            .dropFirst()
            .sink { [weak self] _ in self?.persistAndRefresh() }
            .store(in: &cancellables)

        $displayMode
            .dropFirst()
            .sink { [weak self] _ in self?.persistAndRefresh() }
            .store(in: &cancellables)

        $showMenuValue
            .dropFirst()
            .sink { [weak self] _ in self?.persistAndRefresh() }
            .store(in: &cancellables)

        $persistOverflowState
            .dropFirst()
            .sink { [weak self] _ in self?.persist() }
            .store(in: &cancellables)
    }

    private func configureTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    /// Recomputes visibility, progress and display text for the menu bar item.
    func refresh() {
        let now = Date()
        let todayComponents = Calendar.current.dateComponents([.year, .month, .day], from: now)
        if todayComponents != lastCompletionDay {
            hasTriggeredCompletionForCurrentDay = false
        }

        let weekdayIndex = Calendar.current.component(.weekday, from: now)
        guard let weekday = Weekday(rawValue: weekdayIndex), let scheduledBlocks = workBlocks[weekday], !scheduledBlocks.isEmpty else {
            progress = 0
            displayText = "Outside scheduled days"
            menuValueText = ""
            isActive = false
            return
        }

        let schedule = buildSchedule(from: scheduledBlocks, on: now)
        guard !schedule.isEmpty else {
            progress = 0
            displayText = "End time must be later than start time"
            menuValueText = ""
            isActive = false
            return
        }

        let totalDuration = schedule.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        guard totalDuration > 0 else {
            progress = 0
            displayText = "Configure working hours"
            isActive = false
            menuValueText = ""
            return
        }

        let firstStart = schedule.first!.start
        let lastEnd = schedule.last!.end

        if now < firstStart {
            progress = 1
            displayText = formattedScheduleRange(start: firstStart, end: lastEnd)
            menuValueText = ""
            isActive = false
            hasTriggeredCompletionForCurrentDay = false
            return
        }

        if now >= lastEnd {
            progress = 0
            displayText = "Workday completed"
            if showMenuValue {
                menuValueText = formattedMenuValue(remaining: 0, total: totalDuration)
            } else {
                menuValueText = ""
            }
            isActive = false
            if !hasTriggeredCompletionForCurrentDay {
                hasTriggeredCompletionForCurrentDay = true
                lastCompletionDay = todayComponents
                onDayComplete?()
            }
            return
        }

        let remaining = remainingTime(from: now, schedule: schedule)
        progress = min(1, max(0, remaining / totalDuration))

        let isInsideBlock = schedule.contains(where: { $0.start <= now && now < $0.end })
        isActive = isInsideBlock
        if isInsideBlock {
            displayText = formattedDisplayText(remaining: remaining, total: totalDuration)
        } else {
            displayText = ""
        }

        if showMenuValue {
            menuValueText = formattedMenuValue(remaining: remaining, total: totalDuration)
        } else {
            menuValueText = ""
        }

        hasTriggeredCompletionForCurrentDay = false
    }

    private func buildSchedule(from blocks: [WorkBlock], on date: Date) -> [(block: WorkBlock, start: Date, end: Date)] {
        blocks
            .sorted { $0.start.totalMinutes < $1.start.totalMinutes }
            .compactMap { block -> (block: WorkBlock, start: Date, end: Date)? in
                guard let start = block.startDate(on: date), let end = block.endDate(on: date), start < end else { return nil }
                return (block, start, end)
            }
    }

    private func remainingTime(from currentDate: Date, schedule: [(block: WorkBlock, start: Date, end: Date)]) -> TimeInterval {
        schedule.reduce(0) { partialResult, item in
            if currentDate < item.start {
                return partialResult + item.end.timeIntervalSince(item.start)
            }
            if currentDate >= item.end {
                return partialResult
            }
            return partialResult + item.end.timeIntervalSince(currentDate)
        }
    }

    private func formattedDisplayText(remaining: TimeInterval, total: TimeInterval) -> String {
        switch displayMode {
        case .percentage:
            let percentage = total == 0 ? 0 : (remaining / total)
            let value = Int(round(percentage * 100))
            return "\(value)% of workday remaining"
        case .hours:
            let hours = remaining / 3600
            return String(format: "%.1fh left", hours)
        case .hoursAndMinutes:
            let hours = Int(remaining / 3600)
            let minutes = Int((remaining.truncatingRemainder(dividingBy: 3600)) / 60)
            if hours > 0 {
                return "\(hours)h \(minutes)m left"
            } else {
                return "\(minutes)m left"
            }
        }
    }

    private func formattedMenuValue(remaining: TimeInterval, total: TimeInterval) -> String {
        switch displayMode {
        case .percentage:
            let percentage = total == 0 ? 0 : (remaining / total)
            let value = Int(round(percentage * 100))
            return "\(value)%"
        case .hours:
            let hours = remaining / 3600
            return String(format: "%.1fh", hours)
        case .hoursAndMinutes:
            let hours = Int(remaining / 3600)
            let minutes = Int((remaining.truncatingRemainder(dividingBy: 3600)) / 60)
            if hours > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(minutes)m"
            }
        }
    }

    private func persistAndRefresh() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.persist()
            self.refresh()
        }
    }

    private func persist() {
        let filteredBlocks = workBlocks.reduce(into: [Int: [WorkBlock]]()) { partialResult, entry in
            guard !entry.value.isEmpty else { return }
            partialResult[entry.key.rawValue] = entry.value
        }

        let settings = WorkdaySettings(
            selectedWeekdays: Array(filteredBlocks.keys),
            displayMode: displayMode.rawValue,
            showMenuValue: showMenuValue,
            persistOverflowState: persistOverflowState,
            workBlocks: filteredBlocks
        )

        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: settingsKey)
        }
    }

    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private func formattedTime(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    private func formattedScheduleRange(start: Date, end: Date) -> String {
        "\(formattedTime(start)) - \(formattedTime(end))"
    }
}
