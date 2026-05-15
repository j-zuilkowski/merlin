import Foundation

/// Result of the manual-coverage release gate check.
enum BaselineCheckResult: Sendable {
    case pass
    case fail(reason: String)
}

private struct BaselineSnapshot: Codable {
    let date: Date
    let uncoveredCount: Int
}

/// Tracks and enforces the decaying manual-coverage baseline across releases.
actor ManualBaselineManager {

    // MARK: - API

    func currentBaseline(projectPath: String) async -> Int {
        snapshots(projectPath: projectPath).last?.uncoveredCount ?? 0
    }

    func recordRelease(projectPath: String, uncoveredCount: Int) async throws {
        var list = snapshots(projectPath: projectPath)
        list.append(BaselineSnapshot(date: Date(), uncoveredCount: uncoveredCount))
        let data = try JSONEncoder().encode(list)
        let url = baselineURL(projectPath: projectPath)
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent, withIntermediateDirectories: true, attributes: nil)
        try data.write(to: url, options: .atomic)
    }

    func releaseGateCheck(
        projectPath: String,
        uncoveredCount: Int,
        config: ProjectConfig
    ) async -> BaselineCheckResult {
        let list = snapshots(projectPath: projectPath)

        if let last = list.last {
            if uncoveredCount > last.uncoveredCount {
                return .fail(
                    reason: "Uncovered surfaces increased: \(last.uncoveredCount) → \(uncoveredCount). No new surfaces without coverage."
                )
            }

            let required = max(0, last.uncoveredCount - config.decayPerRelease)
            if uncoveredCount > required && last.uncoveredCount > 0 {
                return .fail(
                    reason: "Baseline did not decay enough. Was \(last.uncoveredCount), now \(uncoveredCount). Required ≤ \(required) (decay: \(config.decayPerRelease))."
                )
            }
        } else if uncoveredCount > config.manualCoverageBaseline {
            return .fail(
                reason: "Uncovered surfaces (\(uncoveredCount)) exceed initial baseline (\(config.manualCoverageBaseline))."
            )
        }

        return .pass
    }

    // MARK: - Persistence

    private func baselineURL(projectPath: String) -> URL {
        URL(fileURLWithPath: projectPath)
            .appendingPathComponent(".merlin")
            .appendingPathComponent("manual-coverage-baseline.json")
    }

    private func snapshots(projectPath: String) -> [BaselineSnapshot] {
        guard let data = try? Data(contentsOf: baselineURL(projectPath: projectPath)),
              let list = try? JSONDecoder().decode([BaselineSnapshot].self, from: data)
        else {
            return []
        }
        return list
    }
}
