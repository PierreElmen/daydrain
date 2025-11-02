import Foundation
import Combine

struct DailyNote: Codable, Equatable {
    var date: String
    var content: String
    var updatedAt: Date
}

final class NotesManager {
    enum RetentionPolicy: Int {
        case seven = 7
        case thirty = 30
        case ninety = 90
        case year = 365
        case never = -1

        var keepDays: Int? {
            rawValue > 0 ? rawValue : nil
        }
    }

    private enum Constants {
        static let retentionDefaultsKey = "NotesRetentionDays"
        static let directoryName = "DayDrain"
        static let notesSubdirectory = "notes"
        static let saveDebounceInterval: TimeInterval = 0.5
    }

    private let fileManager = FileManager.default
    private let baseDirectory: URL
    private let notesDirectory: URL
    private var cache: [String: DailyNote]
    private var subjects: [String: CurrentValueSubject<DailyNote, Never>]
    private var saveWorkItems: [String: DispatchWorkItem]
    private let queue = DispatchQueue(label: "co.daydrain.notes", qos: .userInitiated)
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let defaults: UserDefaults

    private var retentionDays: Int? {
        get {
            let stored = defaults.integer(forKey: Constants.retentionDefaultsKey)
            if defaults.object(forKey: Constants.retentionDefaultsKey) == nil { return RetentionPolicy.thirty.keepDays }
            return stored > 0 ? stored : nil
        }
        set {
            if let days = newValue, days > 0 {
                defaults.set(days, forKey: Constants.retentionDefaultsKey)
            } else {
                defaults.set(-1, forKey: Constants.retentionDefaultsKey)
            }
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        defaults = userDefaults
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        baseDirectory = base.appendingPathComponent(Constants.directoryName, isDirectory: true)
        notesDirectory = baseDirectory.appendingPathComponent(Constants.notesSubdirectory, isDirectory: true)
        cache = [:]
        subjects = [:]
        saveWorkItems = [:]
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        ensureDirectories()
        _ = ensureNoteExists(for: Date())
        pruneOldNotes()
    }

    func publisher(for date: Date) -> AnyPublisher<DailyNote, Never> {
        let iso = isoString(for: date)
        let subject: CurrentValueSubject<DailyNote, Never> = queue.sync {
            let note = ensureNoteExists(forISODate: iso)
            let subject = subjectForISODate(iso, initialValue: note)
            if subject.value != note {
                subject.send(note)
            }
            return subject
        }
        return subject.eraseToAnyPublisher()
    }

    func currentNote(for date: Date) -> DailyNote {
        queue.sync {
            ensureNoteExists(forISODate: isoString(for: date))
        }
    }

    func updateContent(_ content: String, for date: Date) {
        queue.async { [weak self] in
            guard let self else { return }
            let iso = self.isoString(for: date)
            var note = self.ensureNoteExists(forISODate: iso)
            if note.content == content {
                return
            }
            note.content = content
            note.updatedAt = Date()
            self.cache[iso] = note
            let subject = self.subjectForISODate(iso, initialValue: note)
            subject.send(note)
            self.scheduleSave(note, forISODate: iso)
        }
    }

    func forceSaveCurrentNote(for date: Date) {
        queue.async { [weak self] in
            guard let self else { return }
            let iso = self.isoString(for: date)
            let note = self.ensureNoteExists(forISODate: iso)
            self.persist(note, forISODate: iso)
        }
    }

    func refreshForCurrentDay(reference date: Date = Date()) -> DailyNote {
        queue.sync {
            ensureNoteExists(for: date)
        }
    }

    func noteContent(for date: Date) -> String {
        queue.sync {
            ensureNoteExists(forISODate: isoString(for: date)).content
        }
    }

    func copyNote(for date: Date) -> DailyNote {
        queue.sync {
            ensureNoteExists(forISODate: isoString(for: date))
        }
    }

    func setRetentionPolicy(_ policy: RetentionPolicy) {
        retentionDays = policy.keepDays
        pruneOldNotes()
    }

    func pruneOldNotes(keepDays: Int? = nil) {
        let keep = keepDays ?? retentionDays
        guard let keep, keep > 0 else { return }
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -keep, to: Date()) ?? Date()
        let cutoffISO = isoString(for: cutoffDate)

        queue.async { [weak self] in
            guard let self else { return }
            guard let fileNames = try? self.fileManager.contentsOfDirectory(atPath: self.notesDirectory.path) else { return }
            for name in fileNames where name.hasSuffix(".json") {
                let iso = String(name.dropLast(5))
                if iso < cutoffISO {
                    let url = self.notesDirectory.appendingPathComponent(name)
                    try? self.fileManager.removeItem(at: url)
                    self.cache.removeValue(forKey: iso)
                    self.subjects.removeValue(forKey: iso)
                }
            }
        }
    }

    // MARK: - Private

    private func ensureDirectories() {
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }
        if !fileManager.fileExists(atPath: notesDirectory.path) {
            try? fileManager.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        }
    }

    @discardableResult
    private func ensureNoteExists(for date: Date) -> DailyNote {
        ensureNoteExists(forISODate: isoString(for: date))
    }

    @discardableResult
    private func ensureNoteExists(forISODate iso: String) -> DailyNote {
        if let cached = cache[iso] {
            return cached
        }

        let url = notesDirectory.appendingPathComponent("\(iso).json")
        if let data = try? Data(contentsOf: url),
           let decoded = try? decoder.decode(DailyNote.self, from: data) {
            cache[iso] = decoded
            return decoded
        }

        let note = DailyNote(date: iso, content: "", updatedAt: Date())
        cache[iso] = note
        persist(note, forISODate: iso)
        return note
    }

    private func subjectForISODate(_ iso: String, initialValue: DailyNote) -> CurrentValueSubject<DailyNote, Never> {
        if let subject = subjects[iso] {
            return subject
        }
        let subject = CurrentValueSubject<DailyNote, Never>(initialValue)
        subjects[iso] = subject
        return subject
    }

    private func scheduleSave(_ note: DailyNote, forISODate iso: String) {
        if let existing = saveWorkItems[iso] {
            existing.cancel()
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.persist(note, forISODate: iso)
        }
        saveWorkItems[iso] = workItem
        queue.asyncAfter(deadline: .now() + Constants.saveDebounceInterval, execute: workItem)
    }

    private func persist(_ note: DailyNote, forISODate iso: String) {
        let url = notesDirectory.appendingPathComponent("\(iso).json")
        guard let data = try? encoder.encode(note) else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            // Best effort persistence; ignore failures for now.
        }
    }

    private func isoString(for date: Date) -> String {
        Self.isoFormatter.string(from: date)
    }

    private static let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}
