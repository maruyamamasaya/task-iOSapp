import Foundation
import Combine

@MainActor final class DailyBriefStore: ObservableObject {
    @Published private(set) var brief: DailyBrief?
    @Published private(set) var errorMessage: String?
    @Published private(set) var context: DailyBriefContext?
    private let repository: any DailyBriefRepository
    private var generation = 0

    init(repository: any DailyBriefRepository) { self.repository = repository }

    var isOutdated: Bool { brief.map { $0.contextID != context?.id } ?? false }

    func refresh(_ input: DailyBriefContext) async {
        generation += 1
        let requestGeneration = generation
        if context?.date != input.date || context?.timeZone != input.timeZone {
            brief = nil
        }
        context = input
        do {
            if let saved = try repository.cached(for: input), saved.date == input.date, saved.timeZone == input.timeZone { brief = saved }
            let received = try await repository.exchange(input)
            guard requestGeneration == generation, !Task.isCancelled else { return }
            if let received {
                guard received.date == input.date, received.timeZone == input.timeZone else { throw CocoaError(.coderInvalidValue) }
                brief = received
            }
            errorMessage = nil
        } catch {
            guard requestGeneration == generation, !Task.isCancelled else { return }
            errorMessage = "Dotとの受け渡しを確認できません。Macへの接続後に更新します。"
        }
    }
}
