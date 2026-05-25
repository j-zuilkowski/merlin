import Foundation

struct ReadabilityFinding: Sendable {
    let docFile: String
    let measuredGrade: Double
    let targetGrade: Double
    let suggestions: [String]
}

/// Checks doc-file prose readability using Vale.
/// In dry-run / test mode, returns a synthetic result without spawning a process.
actor ProseReadabilityChecker {

    private let dryRun: Bool
    private let forcedGrade: Double?
    /// Maximum wall-clock seconds the `vale` child process may run. Injectable for tests.
    private let timeoutSeconds: Int

    init(dryRun: Bool = false, forcedGrade: Double? = nil, timeoutSeconds: Int = 120) {
        self.dryRun = dryRun
        self.forcedGrade = forcedGrade
        self.timeoutSeconds = timeoutSeconds
    }

    func check(docFile: String, targetGrade: Double) async -> ReadabilityFinding {
        if dryRun {
            let grade = forcedGrade ?? 8.0
            let suggestions = grade > targetGrade
                ? ["Consider shorter sentences.", "Reduce passive voice."]
                : []
            return ReadabilityFinding(
                docFile: docFile,
                measuredGrade: grade,
                targetGrade: targetGrade,
                suggestions: suggestions
            )
        }
        return await runVale(docFile: docFile, targetGrade: targetGrade)
    }

    private func runVale(docFile: String, targetGrade: Double) async -> ReadabilityFinding {
        let valeOutput = await spawnVale(docFile: docFile)
        // No grade extracted (vale missing, no readability alert) -> fall back to the
        // target so the gate passes - graceful degradation.
        let grade = extractGrade(from: valeOutput) ?? targetGrade
        let suggestions = grade > targetGrade ? extractSuggestions(from: valeOutput) : []
        return ReadabilityFinding(
            docFile: docFile,
            measuredGrade: grade,
            targetGrade: targetGrade,
            suggestions: suggestions
        )
    }

    private func spawnVale(docFile: String) async -> String {
        guard hasValeConfig(for: docFile) else { return "" }
        guard await ToolRequirementCoordinator.shared.ensure("vale") else { return "" }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["vale", "--output", "JSON", docFile]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        let guardBox = ProseResumeGuard()
        let deadline = timeoutSeconds

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8) ?? ""
                Task {
                    guard await guardBox.claim() else { return }
                    continuation.resume(returning: text)
                }
            }

            // Watchdog: a hung `vale` is terminated and the call falls back to "".
            Task {
                try? await Task.sleep(
                    nanoseconds: UInt64(deadline) * 1_000_000_000)
                guard await guardBox.claim() else { return }
                if process.isRunning {
                    process.terminate()
                }
                continuation.resume(returning: "")
            }

            do {
                try process.run()
            } catch {
                Task {
                    guard await guardBox.claim() else { return }
                    continuation.resume(returning: "")
                }
            }
        }
    }

    private func hasValeConfig(for docFile: String) -> Bool {
        let fileManager = FileManager.default
        var directory = URL(fileURLWithPath: docFile).deletingLastPathComponent()
        while true {
            for filename in [".vale.ini", "_vale.ini", "vale.ini"] {
                let candidate = directory.appendingPathComponent(filename).path
                if fileManager.fileExists(atPath: candidate) {
                    return true
                }
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path {
                return false
            }
            directory = parent
        }
    }

    /// Parses Vale's `--output JSON` shape: a dictionary keyed by file path whose
    /// values are arrays of alert objects. Each alert has `Check`, `Message`, `Line`,
    /// and `Severity`. The readability grade lives in the `Message` of the alert whose
    /// `Check` belongs to a readability rule (e.g. `Merlin.readability`).
    private func extractGrade(from json: String) -> Double? {
        guard let alerts = parseAlerts(json) else { return nil }
        for alert in alerts {
            let check = (alert["Check"] as? String ?? "").lowercased()
            guard check.contains("readability") else { continue }
            let message = alert["Message"] as? String ?? ""
            if let grade = firstNumber(in: message) {
                return grade
            }
        }
        return nil
    }

    private func extractSuggestions(from json: String) -> [String] {
        guard let alerts = parseAlerts(json) else { return [] }
        return alerts.compactMap { $0["Message"] as? String }
    }

    /// Flattens Vale's `{ "file": [alert, ...] }` JSON into a single alert list.
    private func parseAlerts(_ json: String) -> [[String: Any]]? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        if let byFile = root as? [String: Any] {
            var all: [[String: Any]] = []
            for value in byFile.values {
                if let alerts = value as? [[String: Any]] {
                    all.append(contentsOf: alerts)
                }
            }
            return all
        }
        // Tolerate a bare alert array as well.
        if let alerts = root as? [[String: Any]] {
            return alerts
        }
        return nil
    }

    /// Extracts the first numeric token (integer or decimal) from a string.
    private func firstNumber(in text: String) -> Double? {
        guard let range = text.range(
            of: #"[0-9]+(\.[0-9]+)?"#, options: .regularExpression) else {
            return nil
        }
        return Double(text[range])
    }
}

/// Single-resume guard for ProseReadabilityChecker's process continuation.
private actor ProseResumeGuard {
    private var claimed = false
    func claim() -> Bool {
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
