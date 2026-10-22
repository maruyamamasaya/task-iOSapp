import Foundation
import DotLocalBridge

@MainActor final class DotDailyBriefRepository: DailyBriefRepository {
    private let directory: URL
    private let pairing: @MainActor () throws -> RelayPairing?
    init(directory: URL = URL.applicationSupportDirectory.appending(path: "DotDailyBrief"),
         pairing: @escaping @MainActor () throws -> RelayPairing? = { try KeychainRelayPairing().load() }) {
        self.directory = directory; self.pairing = pairing
    }
    private func file(_ context: DailyBriefContext, bridgeID: String) -> URL {
        // Pairing identity is part of the cache key: another Mac's prose is never reused.
        directory.appending(path: bridgeID).appending(path: context.date + "-" + context.timeZone.replacingOccurrences(of: "/", with: "_") + ".json")
    }
    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder
    }
    func cached(for context: DailyBriefContext) throws -> DailyBrief? {
        guard let pair = try pairing() else { return nil }
        let url = file(context, bridgeID: pair.bridgeID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let brief = try decoder().decode(DailyBrief.self, from: Data(contentsOf: url))
        guard brief.date == context.date, brief.timeZone == context.timeZone else { return nil }
        return brief
    }
    func exchange(_ context: DailyBriefContext) async throws -> DailyBrief? {
        guard let pair = try pairing() else { throw BridgeNetworkError.unavailable }
        let input = try context.encodedInput()
        let data = try await pair.transport().exchangeDailyBrief(inputJSON: input)
        struct Response: Decodable { let brief: DailyBrief? }
        guard let brief = try decoder().decode(Response.self, from: data).brief else { return nil }
        guard brief.date == context.date, brief.timeZone == context.timeZone,
              ["outlook", "reflection"].contains(brief.kind), !brief.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              brief.text.count <= 2000 else { throw BridgeNetworkError.unexpectedResponse }
        let url = file(context, bridgeID: pair.bridgeID)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(brief).write(to: url, options: [.atomic, .completeFileProtection])
        return brief
    }
}
