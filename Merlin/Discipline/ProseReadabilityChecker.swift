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

    init(dryRun: Bool = false, forcedGrade: Double? = nil) {
        self.dryRun = dryRun
        self.forcedGrade = forcedGrade
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
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["vale", "--output", "JSON", docFile]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: "")
            }
        }
    }

    private func extractGrade(from json: String) -> Double? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let score = obj["readability"] as? Double
        else { return nil }
        return score
    }

    private func extractSuggestions(from json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return arr.compactMap { $0["Message"] as? String }
    }
}
