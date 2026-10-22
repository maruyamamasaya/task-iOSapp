import Foundation

@MainActor final class DotTaskFileCache: DotTaskCache {
    private let url: URL
    init(url: URL) { self.url = url }
    func load() throws -> DotTaskSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(DotTaskSnapshot.self, from: Data(contentsOf: url))
    }
    func save(_ snapshot: DotTaskSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }
}

// The device-local namespace deliberately differs from sample and remote accounts.
@MainActor struct LocalDotTaskSource: DotTaskSource {
    let source = "dot-local-json-v1"
    let account = "on-device"
    let cache: any DotTaskCache

    func fetch() async throws -> DotTaskFeed {
        guard let value = try cache.load() else { throw DotTaskError.noLocalData }
        return DotTaskFeed(updatedAt: value.updatedAt, tasks: value.tasks)
    }
}

@MainActor struct DotTaskJSONFileImporter: DotTaskFileImporting {
    static let maximumBytes = 5 * 1024 * 1024

    func read(from url: URL) throws -> DotTaskFeed {
        guard url.isFileURL else { throw DotTaskError.invalidFeed }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maximumBytes + 1) ?? Data()
        guard data.count <= Self.maximumBytes else { throw DotTaskError.invalidFeed }
        // Validate before saving: malformed JSON never overwrites the last good copy.
        return try DotTaskFeedDecoder.decode(data)
    }
}
