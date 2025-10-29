import Foundation

final class OverflowManager {
    private let weekManager: WeekManager

    init(weekManager: WeekManager) {
        self.weekManager = weekManager
    }

    func tasks(for date: Date) -> [OverflowTask] {
        weekManager.snapshot(for: date).overflow
    }

    @discardableResult
    func updateTasks(on date: Date, transform: (inout [OverflowTask]) -> Void) -> [OverflowTask] {
        var snapshot = weekManager.snapshot(for: date)
        transform(&snapshot.overflow)
        weekManager.save(snapshot: snapshot)
        return snapshot.overflow
    }

    func setCollapsed(_ collapsed: Bool, on date: Date) -> DailyUIState {
        var snapshot = weekManager.snapshot(for: date)
        if snapshot.uiState.isOverflowCollapsed != collapsed {
            snapshot.uiState.isOverflowCollapsed = collapsed
            weekManager.save(snapshot: snapshot)
        }
        return snapshot.uiState
    }

    func uiState(for date: Date) -> DailyUIState {
        weekManager.snapshot(for: date).uiState
    }
}
