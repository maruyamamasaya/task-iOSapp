import Foundation

protocol DateProviding: Sendable { var now: Date { get } }

struct SystemDateProvider: DateProviding { var now: Date { Date() } }

struct FixedDateProvider: DateProviding {
    let now: Date
}
