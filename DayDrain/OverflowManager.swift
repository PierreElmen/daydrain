import Foundation

final class OverflowManager {
    private let textLimit = 80

    func addTask(text: String, to snapshot: inout DailyFocusSnapshot) -> OverflowTask? {
        let trimmed = sanitize(text)
        guard !trimmed.isEmpty else { return nil }
        let task = OverflowTask(text: trimmed, done: false)
        snapshot.overflow.append(task)
        return task
    }

    func updateTask(id: UUID, text: String, in snapshot: inout DailyFocusSnapshot) {
        guard let index = snapshot.overflow.firstIndex(where: { $0.id == id }) else { return }
        snapshot.overflow[index].text = sanitize(text)
        if snapshot.overflow[index].text.isEmpty {
            snapshot.overflow.remove(at: index)
        }
    }

    func toggleTask(id: UUID, in snapshot: inout DailyFocusSnapshot) {
        guard let index = snapshot.overflow.firstIndex(where: { $0.id == id }) else { return }
        snapshot.overflow[index].done.toggle()
    }

    func removeTask(id: UUID, from snapshot: inout DailyFocusSnapshot) -> OverflowTask? {
        guard let index = snapshot.overflow.firstIndex(where: { $0.id == id }) else { return nil }
        return snapshot.overflow.remove(at: index)
    }

    func moveFromFocus(task: FocusTask, into snapshot: inout DailyFocusSnapshot) -> OverflowTask? {
        let trimmed = sanitize(task.text)
        guard !trimmed.isEmpty else { return nil }
        let overflowTask = OverflowTask(text: trimmed, done: false)
        snapshot.overflow.append(overflowTask)
        return overflowTask
    }

    func moveToInbox(id: UUID, from snapshot: inout DailyFocusSnapshot) -> OverflowTask? {
        guard let index = snapshot.overflow.firstIndex(where: { $0.id == id }) else { return nil }
        return snapshot.overflow.remove(at: index)
    }

    private func sanitize(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(textLimit))
    }
}
