import Foundation

/// Result of a single `DisciplineEngine.scan` run.
struct ScanReport: Sendable {
    let findings: [Finding]
    let durationMs: Int
    let scannedAt: Date
}
