import Foundation

/// Capability-based role slots for the supervisor-worker architecture.
///
/// - `execute`: cheap/fast local model — bulk execution, routine tasks
/// - `reason`: thinking/reasoning model — verification, critic, high-stakes work
/// - `orchestrate`: planning model — task decomposition; defaults to `reason` if unassigned
/// - `vision`: vision-capable model — screenshot analysis, UI inspection
enum AgentSlot: String, CaseIterable, Codable, Hashable, Sendable {
    case execute
    case reason
    case orchestrate
    case vision
}
