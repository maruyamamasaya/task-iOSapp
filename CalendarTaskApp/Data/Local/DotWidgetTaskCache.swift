import Foundation

// Display-only projection. Never used to write back to the Mac canonical source.
struct DotWidgetTask: Codable, Equatable, Identifiable {
    let id: UUID
    let title: String
    let date: Date?
    let isAllDay: Bool
    let isCompleted: Bool
    var calendarDate: String? = nil

    func resolvedDate(calendar: Calendar) -> Date? {
        guard let calendarDate else { return date }
        let formatter = DateFormatter()
        var gregorian = Calendar(identifier: .gregorian); gregorian.timeZone = calendar.timeZone
        formatter.calendar = gregorian; formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let parsed = formatter.date(from: calendarDate), formatter.string(from: parsed) == calendarDate else { return nil }
        return parsed
    }
}

struct DotWidgetTaskCache {
    let url: URL
    private struct Snapshot: Codable {
        let version: Int
        let tasks: [DotWidgetTask]
    }

    static func shared(bundle: Bundle = .main) -> Self? {
        guard let identifier = bundle.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String,
              !identifier.isEmpty,
              let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else { return nil }
        return Self(url: directory.appending(path: "DotTasks/widget-v1.json"))
    }

    func load() throws -> [DotWidgetTask] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
        guard snapshot.version == 1 else { throw CocoaError(.coderReadCorrupt) }
        return snapshot.tasks
    }

    @discardableResult func save(_ tasks: [TaskItem], calendar: Calendar = .current) throws -> Bool {
        let formatter = DateFormatter()
        var gregorian = Calendar(identifier: .gregorian); gregorian.timeZone = calendar.timeZone
        formatter.calendar = gregorian; formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let rows = tasks.map {
            DotWidgetTask(id: $0.id, title: $0.title, date: $0.dueDate ?? $0.startDate,
                          isAllDay: $0.isAllDay, isCompleted: $0.isCompleted,
                          calendarDate: $0.isAllDay ? ($0.dueDate ?? $0.startDate).map { formatter.string(from: $0) } : nil)
        }
        if let previous = try? load(), previous == rows, FileManager.default.fileExists(atPath: url.path) { return false }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Snapshot(version: 1, tasks: rows)).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return true
    }
}
