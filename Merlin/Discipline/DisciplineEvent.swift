import Foundation

/// One structured event emitted by `merlin-discipline` during a gate run, written to
/// `<project>/.merlin/discipline-events.jsonl` so the app can observe CLI activity.
struct DisciplineEvent: Codable, Sendable {
    let timestamp: Date
    let subcommand: String
    let step: String
    let detail: String
    let passed: Bool?
}
