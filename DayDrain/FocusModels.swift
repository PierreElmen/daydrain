import Foundation

struct FocusTask: Identifiable, Codable, Equatable {
    let label: String
    var text: String
    var done: Bool
    var note: String

    var id: String { label }
}

struct OverflowTask: Codable, Equatable {
    var text: String
    var done: Bool

    func sanitized() -> OverflowTask {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let limited = String(trimmed.prefix(160))
        return OverflowTask(text: limited, done: done)
    }
}

enum InboxPriority: String, Codable, CaseIterable {
    case must
    case medium
    case nice

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self).lowercased()
        switch raw {
        case "must", "essential":
            self = .must
        case "medium", "meaningful":
            self = .medium
        case "nice", "optional":
            self = .nice
        default:
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported priority value: \(raw)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct InboxTask: Codable, Equatable {
    var text: String
    var priority: InboxPriority
    var done: Bool

    func sanitized() -> InboxTask {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let limited = String(trimmed.prefix(160))
        return InboxTask(text: limited, priority: priority, done: done)
    }
}

struct DailyUIState: Codable, Equatable {
    var isOverflowCollapsed: Bool
    var isInboxCollapsed: Bool

    init(isOverflowCollapsed: Bool = true, isInboxCollapsed: Bool = false) {
        self.isOverflowCollapsed = isOverflowCollapsed
        self.isInboxCollapsed = isInboxCollapsed
    }

    func sanitized() -> DailyUIState {
        DailyUIState(isOverflowCollapsed: isOverflowCollapsed, isInboxCollapsed: isInboxCollapsed)
    }
}

struct DailyFocusSnapshot: Codable {
    var date: String
    var tasks: [FocusTask]
    var mood: Int?
    var overflow: [OverflowTask]
    var inbox: [InboxTask]?
    var uiState: DailyUIState

    init(date: String, tasks: [FocusTask], mood: Int?, overflow: [OverflowTask] = [], inbox: [InboxTask]? = nil, uiState: DailyUIState = DailyUIState()) {
        self.date = date
        self.tasks = tasks
        self.mood = mood
        self.overflow = overflow
        self.inbox = inbox
        self.uiState = uiState
    }

    private enum CodingKeys: String, CodingKey {
        case date
        case tasks
        case focus
        case mood
        case overflow
        case inbox
        case uiState
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(String.self, forKey: .date)
        if let focusTasks = try container.decodeIfPresent([FocusTask].self, forKey: .focus) {
            tasks = focusTasks
        } else if let legacyTasks = try container.decodeIfPresent([FocusTask].self, forKey: .tasks) {
            tasks = legacyTasks
        } else {
            tasks = []
        }
        mood = try container.decodeIfPresent(Int.self, forKey: .mood)
        overflow = try container.decodeIfPresent([OverflowTask].self, forKey: .overflow) ?? []
        inbox = try container.decodeIfPresent([InboxTask].self, forKey: .inbox)
        uiState = try container.decodeIfPresent(DailyUIState.self, forKey: .uiState) ?? DailyUIState()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encode(tasks, forKey: .focus)
        try container.encode(mood, forKey: .mood)
        if !overflow.isEmpty {
            try container.encode(overflow, forKey: .overflow)
        }
        if let inbox {
            try container.encode(inbox, forKey: .inbox)
        }
        try container.encode(uiState, forKey: .uiState)
    }
}

struct WeekSummary {
    struct DayBreakdown: Identifiable {
        let date: Date
        let completed: Int
        let total: Int
        let mood: Int?

        var id: Date { date }
    }

    var completed: Int
    var total: Int
    var averageMood: Double?
    var dayBreakdown: [DayBreakdown]

    static var empty: WeekSummary {
        WeekSummary(completed: 0, total: 0, averageMood: nil, dayBreakdown: [])
    }
}

extension WeekSummary {
    var completionText: String {
        guard total > 0 else { return "No focus tasks logged this week" }
        return "\(completed) / \(total) tasks completed this week"
    }

    var averageMoodEmoji: String? {
        guard let averageMood else { return nil }
        let rounded = Int((averageMood).rounded())
        switch rounded {
        case ..<2:
            return "😫"
        case 2:
            return "😕"
        case 3:
            return "😐"
        case 4:
            return "🙂"
        default:
            return "😄"
        }
    }

    var averageMoodTooltip: String? {
        guard let averageMood else { return nil }
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        let value = formatter.string(from: NSNumber(value: averageMood)) ?? String(format: "%.1f", averageMood)
        return "Average mood this week: \(value)"
    }
}
