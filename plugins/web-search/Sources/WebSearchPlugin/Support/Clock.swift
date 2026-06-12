import Foundation

protocol ClockProvider: Sendable {
    func now() -> Date
}

struct SystemClock: ClockProvider {
    func now() -> Date { Date() }
}

struct FixedClock: ClockProvider {
    let fixedDate: Date

    func now() -> Date { fixedDate }
}
