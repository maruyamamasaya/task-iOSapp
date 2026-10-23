import Foundation
import DotLocalBridge

// Wire DTOs never enter SwiftData or the existing whole-database backup restore.
struct DotTaskFeedDecoder {
    private struct Document: Decodable {
        let updatedAt: String
        let tasks: [Row]
    }
    private struct Row: Decodable {
        let id: String
        let title: String
        let date: String?
        let dateLabel: String
        let status: String
        let details: String
        let category: String
        let subcategory: String?
        let parentId: String?
        let taskKind: String?
        let aiContext: String?
        let startTime: String?
        let endTime: String?
        let timeZone: String?
        let deadlineDate: String?
        let deadlineTime: String?
    }
    static func decode(_ data: Data) throws -> DotTaskFeed {
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard !document.updatedAt.isEmpty,
              Set(document.tasks.map(\.id)).count == document.tasks.count else { throw DotTaskError.invalidFeed }
        let tasks = try document.tasks.map { row in
            guard !row.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !row.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DotTaskError.invalidFeed }
            if let date = row.date {
                let formatter = DateFormatter()
                formatter.calendar = Calendar(identifier: .gregorian)
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.isLenient = false
                guard let parsed = formatter.date(from: date), formatter.string(from: parsed) == date else {
                    throw DotTaskError.invalidFeed
                }
            }
            let wire = WireTask(id: row.id, title: row.title, date: row.date, dateLabel: row.dateLabel,
                                status: row.status, details: row.details, category: row.category,
                                completed: row.status == "完了", revision: 1,
                                aiContext: row.aiContext, startTime: row.startTime, endTime: row.endTime,
                                timeZone: row.timeZone, deadlineDate: row.deadlineDate, deadlineTime: row.deadlineTime, taskKind: row.taskKind)
            guard wire.hasValidSchedule else { throw DotTaskError.invalidFeed }
            return DotTaskRecord(id: UUID(), slug: row.id, title: row.title, date: row.date,
                dateLabel: row.dateLabel, status: row.status, details: row.details, category: row.category,
                subcategory: row.subcategory, parentId: row.parentId,
                taskKind: row.taskKind, aiContext: row.aiContext, startTime: row.startTime, endTime: row.endTime,
                timeZone: row.timeZone, deadlineDate: row.deadlineDate, deadlineTime: row.deadlineTime)
        }
        return DotTaskFeed(updatedAt: document.updatedAt, tasks: tasks)
    }
}

@MainActor struct FixtureDotTaskSource: DotTaskSource {
    let source = "dot-fixture-v1"
    let account = "sample-only"
    func fetch() async throws -> DotTaskFeed {
        try DotTaskFeedDecoder.decode(Data(Self.json.utf8))
    }
    // Synthetic examples only. Never label these as the user's live tasks.
    static let json = #"""
    {"updatedAt":"2026-10-21","groups":[],"tasks":[
      {"id":"sample-review","title":"サンプル：連携画面を確認する","date":"2026-10-21","dateLabel":"10月21日","status":"todo","details":"実際の dot のタスクではありません。","category":"開発"},
      {"id":"sample-later","title":"サンプル：あとで検討する","date":null,"dateLabel":"未定","status":"pending","details":"日付未定の例です。","category":"生活","parentId":"sample-review"}
    ]}
    """#
}

// A planner projection, independent of the native SwiftData repository.
struct DotPlannerTask {
    let slug: String
    let task: TaskItem
}

@MainActor final class DotPlannerTaskRepository: TaskRepository {
    private let imported: () throws -> [DotTaskRecord]
    private let relay: () async throws -> [DotPlannerTask]
    private let updateRelay: (TaskItem) async throws -> Void
    private let calendar: Calendar

    init(imported: @escaping () throws -> [DotTaskRecord],
         relay: @escaping () async throws -> [DotPlannerTask],
         updateRelay: @escaping (TaskItem) async throws -> Void,
         calendar: Calendar = .current) {
        self.imported = imported; self.relay = relay; self.updateRelay = updateRelay
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        self.calendar = gregorian
    }

    func fetchTasks() async throws -> [TaskItem] {
        let relayRows = try await relay()
        let slugs = Set(relayRows.map(\.slug))
        return try imported().filter { !slugs.contains($0.slug) }.map(project) + relayRows.map(\.task)
    }

    func addTask(_ task: TaskItem) async throws { throw PlannerError.readOnly }
    func deleteTask(id: UUID) async throws { throw PlannerError.readOnly }
    func updateTask(_ task: TaskItem) async throws {
        guard try await relay().contains(where: { $0.task.id == task.id }) else { throw PlannerError.readOnly }
        try await updateRelay(task)
    }

    private func project(_ row: DotTaskRecord) -> TaskItem {
        let wire = WireTask(id: row.slug, title: row.title, date: row.date, dateLabel: row.dateLabel,
                            status: row.status, details: row.details, category: row.category,
                            completed: row.status == "完了", revision: 1,
                            aiContext: row.aiContext, startTime: row.startTime, endTime: row.endTime,
                            timeZone: row.timeZone, deadlineDate: row.deadlineDate, deadlineTime: row.deadlineTime)
        let date = wire.scheduleDate(calendar: calendar)
        return TaskItem(id: row.id, title: row.title, note: wire.humanDetails,
                        startDate: row.startTime == nil ? nil : date, dueDate: date, isAllDay: row.startTime == nil,
                        isCompleted: row.status == "完了", completedAt: nil,
                        priority: .normal, reminderDate: nil, recurrenceRule: nil,
                        projectID: nil, category: nil, tags: [],
                        createdAt: .distantPast, updatedAt: .distantPast)
    }

    private enum PlannerError: LocalizedError {
        case readOnly
        var errorDescription: String? { "このタスクの変更は dot で行ってください。" }
    }
}
