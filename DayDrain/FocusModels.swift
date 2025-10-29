import Foundation

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
    var mood: Int?
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
