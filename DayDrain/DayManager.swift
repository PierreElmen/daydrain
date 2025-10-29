import SwiftUI
import Combine

/// Represents the user configurable settings that drive the draining bar.
struct WorkdaySettings: Codable {
    struct TimeComponents: Codable {
        var hour: Int
        var minute: Int
    }

    var selectedWeekdays: [Int]
    var startTime: TimeComponents
    var endTime: TimeComponents
    var displayMode: DayDisplayMode.RawValue
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
    @Published var selectedWeekdays: Set<Weekday>
    @Published var startTime: Date
    @Published var endTime: Date
    @Published var displayMode: DayDisplayMode

    @Published private(set) var progress: Double = 0
    @Published private(set) var isActive: Bool = false
    @Published private(set) var displayText: String = ""

    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    private let defaults = UserDefaults.standard
    private let settingsKey = "WorkdaySettings"

    init() {
        let defaults = Self.defaultSettings()
        if let data = self.defaults.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(WorkdaySettings.self, from: data) {
            self.selectedWeekdays = Set(decoded.selectedWeekdays.compactMap(Weekday.init(rawValue:)))
            self.startTime = DayManager.date(from: decoded.startTime) ?? defaults.startTime
            self.endTime = DayManager.date(from: decoded.endTime) ?? defaults.endTime
            self.displayMode = DayDisplayMode(rawValue: decoded.displayMode) ?? .percentage
        } else {
            self.selectedWeekdays = defaults.selectedWeekdays
            self.startTime = defaults.startTime
            self.endTime = defaults.endTime
            self.displayMode = defaults.displayMode
        }

        bindSettingsChanges()
        configureTimer()
        refresh()
    }

    deinit {
        timer?.invalidate()
    }

    private static func defaultSettings() -> (selectedWeekdays: Set<Weekday>, startTime: Date, endTime: Date, displayMode: DayDisplayMode) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let defaultStart = calendar.date(byAdding: DateComponents(hour: 9), to: startOfDay) ?? Date()
        let defaultEnd = calendar.date(byAdding: DateComponents(hour: 17), to: startOfDay) ?? Date()
        return (selectedWeekdays: Set([.monday, .tuesday, .wednesday, .thursday, .friday]),
                startTime: defaultStart,
                endTime: defaultEnd,
                displayMode: .percentage)
    }

    private func bindSettingsChanges() {
        $selectedWeekdays
            .dropFirst()
            .sink { [weak self] _ in self?.persistAndRefresh() }
            .store(in: &cancellables)

        $startTime
            .dropFirst()
            .sink { [weak self] _ in self?.persistAndRefresh() }
            .store(in: &cancellables)

        $endTime
            .dropFirst()
            .sink { [weak self] _ in self?.persistAndRefresh() }
            .store(in: &cancellables)

        $displayMode
            .dropFirst()
            .sink { [weak self] _ in self?.persistAndRefresh() }
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
        let isWorkday = shouldDisplay(on: now)
        isActive = isWorkday

        guard let startOfToday = combine(date: now, with: startTime),
              let endOfToday = combine(date: now, with: endTime) else {
            progress = 0
            displayText = "Configure working hours"
            return
        }

        guard endOfToday > startOfToday else {
            progress = 0
            displayText = "End time must be later than start time"
            return
        }

        guard isWorkday else {
            progress = 0
            displayText = "Outside scheduled days"
            return
        }

        if now < startOfToday {
            progress = 1
            displayText = "Workday starts at \(formattedTime(startOfToday))"
            return
        }

        if now >= endOfToday {
            progress = 0
            displayText = "Workday completed"
            return
        }

        let total = endOfToday.timeIntervalSince(startOfToday)
        let remaining = max(0, endOfToday.timeIntervalSince(now))
        progress = total == 0 ? 0 : min(1, remaining / total)
        displayText = formattedDisplayText(remaining: remaining, total: total)
    }

    private func combine(date: Date, with time: Date) -> Date? {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = 0
        return calendar.date(from: components)
    }

    private func shouldDisplay(on date: Date) -> Bool {
        let weekday = Calendar.current.component(.weekday, from: date)
        return selectedWeekdays.contains(where: { $0.rawValue == weekday })
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

    private func persistAndRefresh() {
        persist()
        refresh()
    }

    private func persist() {
        let settings = WorkdaySettings(
            selectedWeekdays: selectedWeekdays.map { $0.rawValue },
            startTime: DayManager.components(from: startTime),
            endTime: DayManager.components(from: endTime),
            displayMode: displayMode.rawValue
        )

        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: settingsKey)
        }
    }

    private static func date(from components: WorkdaySettings.TimeComponents) -> Date? {
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: DateComponents(hour: components.hour, minute: components.minute), to: base)
    }

    private static func components(from date: Date) -> WorkdaySettings.TimeComponents {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return .init(hour: components.hour ?? 0, minute: components.minute ?? 0)
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
}
