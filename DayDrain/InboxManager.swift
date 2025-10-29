import Foundation

final class InboxManager {
    private let textLimit = 100

    func addItem(text: String, priority: InboxPriority, to items: inout [InboxItem]) -> InboxItem? {
        let sanitized = sanitize(text)
        guard !sanitized.isEmpty else { return nil }
        let item = InboxItem(text: sanitized, priority: priority, done: false)
        items.insert(item, at: 0)
        return item
    }

    func updateText(for id: UUID, text: String, in items: inout [InboxItem]) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].text = sanitize(text)
        if items[index].text.isEmpty {
            items.remove(at: index)
        }
    }

    func updatePriority(for id: UUID, priority: InboxPriority, in items: inout [InboxItem]) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].priority = priority
    }

    func toggleDone(for id: UUID, in items: inout [InboxItem]) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].done.toggle()
    }

    func remove(id: UUID, from items: inout [InboxItem]) -> InboxItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: index)
    }

    func moveToOverflow(id: UUID, from items: inout [InboxItem]) -> InboxItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: index)
    }

    private func sanitize(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(textLimit))
    }
}
