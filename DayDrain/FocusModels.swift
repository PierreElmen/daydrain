import Foundation

struct FocusTask: Identifiable, Codable, Equatable {
    let label: String
    var text: String
    var done: Bool
    var note: String

    var id: String { label }
}

struct OverflowTask: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var done: Bool

    init(id: UUID = UUID(), text: String, done: Bool = false) {
        self.id = id
        self.text = text
        self.done = done
    }
}

enum InboxPriority: String, Codable, CaseIterable, Identifiable {
    case must
    case medium
    case nice

    var id: String { rawValue }

    var label: String {
        switch self {
        case .must:
            return "🔥 Must-do"
        case .medium:
            return "🌿 Medium"
        case .nice:
            return "☁️ Nice-to-do"
        }
    }

    var accentColor: String {
        switch self {
        case .must:
            return "#FF6B4A"
        case .medium:
            return "#6BA47A"
        case .nice:
            return "#8BA6C9"
        }
    }
}

struct InboxItem: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var priority: InboxPriority
    var done: Bool

    init(id: UUID = UUID(), text: String, priority: InboxPriority, done: Bool = false) {
        self.id = id
        self.text = text
        self.priority = priority
        self.done = done
    }
}

struct DailyFocusSnapshot: Codable {
    var date: String
    var tasks: [FocusTask]
    var mood: Int?
    var overflow: [OverflowTask]
    var inbox: [InboxItem]

    init(date: String, tasks: [FocusTask], mood: Int?, overflow: [OverflowTask] = [], inbox: [InboxItem] = []) {
        self.date = date
        self.tasks = tasks
        self.mood = mood
        self.overflow = overflow
        self.inbox = inbox
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
