import Foundation
import Combine

@MainActor final class DotTaskStore: ObservableObject {
    @Published private(set) var snapshot: DotTaskSnapshot?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRefreshing = false
    private let source: any DotTaskSource
    private let cache: any DotTaskCache
    private let importer: (any DotTaskFileImporting)?
    private var didLoad = false

    init(source: any DotTaskSource, cache: any DotTaskCache, importer: (any DotTaskFileImporting)? = nil) {
        self.source = source
        self.cache = cache
        self.importer = importer
    }

    var canImport: Bool { importer != nil }

    func importFile(from url: URL) {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            guard let importer else { throw DotTaskError.importUnavailable }
            let previous = try cache.load()
            if let previous { try validate(previous) }
            try persist(importer.read(from: url), previous: previous)
        } catch { errorMessage = error.localizedDescription }
    }

    func reportImportFailure() {
        errorMessage = "JSON ファイルを開けませんでした。別のファイルを選んでください。"
    }

    func load() {
        guard !didLoad else { return }
        do {
            if let value = try cache.load() {
                try validate(value)
                snapshot = value
            }
            didLoad = true
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            // Always recover the durable identity map, including after a failed initial load.
            let previous = try cache.load()
            if let previous { try validate(previous) }
            let feed = try await source.fetch()
            try persist(feed, previous: previous)
        } catch { errorMessage = error.localizedDescription }
    }

    private func persist(_ feed: DotTaskFeed, previous: DotTaskSnapshot?) throws {
        guard Set(feed.tasks.map(\.slug)).count == feed.tasks.count,
              feed.tasks.allSatisfy({ !$0.slug.isEmpty }) else { throw DotTaskError.invalidFeed }
        var records = previous?.tasks ?? []
        for incoming in feed.tasks {
            if let index = records.firstIndex(where: { $0.slug == incoming.slug }) {
                let old = records[index]
                records[index] = DotTaskRecord(id: old.id, slug: incoming.slug, title: incoming.title,
                    date: incoming.date, dateLabel: incoming.dateLabel, status: incoming.status,
                    details: incoming.details, category: incoming.category,
                    subcategory: incoming.subcategory, parentId: incoming.parentId,
                    aiContext: incoming.aiContext, startTime: incoming.startTime, endTime: incoming.endTime,
                    timeZone: incoming.timeZone, deadlineDate: incoming.deadlineDate, deadlineTime: incoming.deadlineTime)
            } else { records.append(incoming) }
        }
        // Missing rows are retained: absence is not a deletion instruction.
        let value = DotTaskSnapshot(version: 1, source: source.source, account: source.account,
            updatedAt: feed.updatedAt, fetchedAt: .now, tasks: records)
        try cache.save(value)
        snapshot = value
        didLoad = true
        errorMessage = nil
    }

    private func validate(_ value: DotTaskSnapshot) throws {
        guard value.version == 1, value.source == source.source, value.account == source.account,
              Set(value.tasks.map(\.slug)).count == value.tasks.count,
              Set(value.tasks.map(\.id)).count == value.tasks.count else { throw DotTaskError.incompatibleCache }
    }
}
