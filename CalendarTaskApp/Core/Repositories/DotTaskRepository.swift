import Foundation

// Separate from TaskItem: a source date is a calendar day, not an instant.
struct DotTaskRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let slug: String
    var title: String
    var date: String?
    var dateLabel: String
    var status: String
    var details: String
    var category: String
    var subcategory: String?
    var parentId: String?
    var taskKind: String? = nil
    var aiContext: String? = nil
    var startTime: String? = nil
    var endTime: String? = nil
    var timeZone: String? = nil
    var deadlineDate: String? = nil
    var deadlineTime: String? = nil
}

struct DotTaskSnapshot: Codable, Equatable {
    let version: Int
    let source: String
    let account: String
    var updatedAt: String
    var fetchedAt: Date
    var tasks: [DotTaskRecord]
}

struct DotTaskFeed {
    let updatedAt: String
    let tasks: [DotTaskRecord]
}

@MainActor protocol DotTaskSource {
    var source: String { get }
    var account: String { get }
    func fetch() async throws -> DotTaskFeed
}

@MainActor protocol DotTaskCache {
    func load() throws -> DotTaskSnapshot?
    func save(_ snapshot: DotTaskSnapshot) throws
}

@MainActor protocol DotTaskFileImporting {
    func read(from url: URL) throws -> DotTaskFeed
}

enum DotTaskError: LocalizedError {
    case invalidFeed, incompatibleCache, noLocalData, importUnavailable
    var errorDescription: String? {
        switch self {
        case .invalidFeed: "タスクデータの形式が正しくありません。"
        case .incompatibleCache: "キャッシュの形式または利用者が一致しません。"
        case .noLocalData: "JSON ファイルを読み込むと、端末内で閲覧できます。"
        case .importUnavailable: "この一覧では JSON ファイルを読み込めません。"
        }
    }
}
