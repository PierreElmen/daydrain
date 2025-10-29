import Foundation

struct InboxState: Codable, Equatable {
    var tasks: [InboxTask]
    var isCollapsed: Bool

    static let empty = InboxState(tasks: [], isCollapsed: false)

    func sanitized() -> InboxState {
        let sanitizedTasks = tasks.map { $0.sanitized() }
        return InboxState(tasks: sanitizedTasks, isCollapsed: isCollapsed)
    }
}

final class InboxManager {
    private let fileManager = FileManager.default
    private let baseDirectory: URL
    private let inboxURL: URL
    private var cachedState: InboxState?

    init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        baseDirectory = base.appendingPathComponent("DayDrain", isDirectory: true)
        inboxURL = baseDirectory.appendingPathComponent("inbox.json", isDirectory: false)
        ensureDirectory()
    }

    func state() -> InboxState {
        if let cachedState {
            return cachedState
        }

        guard let data = try? Data(contentsOf: inboxURL),
              let decoded = try? JSONDecoder().decode(InboxState.self, from: data) else {
            cachedState = .empty
            return .empty
        }

        let sanitized = decoded.sanitized()
        cachedState = sanitized
        if sanitized != decoded {
            persist(state: sanitized)
        }
        return sanitized
    }

    @discardableResult
    func update(_ transform: (inout InboxState) -> Void) -> InboxState {
        var state = self.state()
        transform(&state)
        return save(state)
    }

    @discardableResult
    func save(_ state: InboxState) -> InboxState {
        let sanitized = state.sanitized()
        cachedState = sanitized
        persist(state: sanitized)
        return sanitized
    }

    private func persist(state: InboxState) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: inboxURL, options: .atomic)
    }

    private func ensureDirectory() {
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }
    }
}
