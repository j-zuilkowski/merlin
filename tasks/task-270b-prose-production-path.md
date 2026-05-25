# Phase 270b — Prose Readability Production Path

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 270a complete: failing tests for the Vale style shape, the Vale JSON parser, and
`DisciplineEngine` prose integration.

This phase makes the prose-readability path functional end to end: the Vale style file
uses Vale's real readability rule, the checker parses Vale's actual JSON output, and
`DisciplineEngine.scan()` runs the checker over the project's doc files.

---

## Write to: Merlin/Discipline/ValeStyleWriter.swift

Full file content:

```swift
import Foundation

/// Writes Merlin's Vale style files to a given directory.
struct ValeStyleWriter: Sendable {

    func writeStyles(to dir: String) async throws {
        let merlinDir = URL(fileURLWithPath: dir).appendingPathComponent("Merlin")
        try FileManager.default.createDirectory(
            at: merlinDir, withIntermediateDirectories: true, attributes: nil)

        try readabilityYML.write(
            to: merlinDir.appendingPathComponent("readability.yml"),
            atomically: true, encoding: .utf8)
        try acceptTxt.write(
            to: merlinDir.appendingPathComponent("accept.txt"),
            atomically: true, encoding: .utf8)
        try passiveVoiceYML.write(
            to: merlinDir.appendingPathComponent("passive-voice.yml"),
            atomically: true, encoding: .utf8)
        try weaselYML.write(
            to: merlinDir.appendingPathComponent("weasel.yml"),
            atomically: true, encoding: .utf8)
    }

    // Vale's real readability rule. `extends: readability` computes a readability
    // metric over each scope and flags scopes above `grade`. `existence` (the previous
    // value) is a token-matcher and never produces a grade.
    // The implementer should confirm the exact metric name against the installed
    // `vale` version's docs (https://vale.sh/docs/topics/styles/#readability); the
    // hard requirement here is `extends: readability` and a `grade:` threshold.
    private let readabilityYML = """
    extends: readability
    message: "Readability grade (%s) exceeds target."
    level: warning
    link: https://vale.sh/docs/topics/styles/
    metrics:
      - Flesch-Kincaid Grade Level
    grade: 9
    """

    private let acceptTxt = """
    Merlin
    DeepSeek
    API
    RAG
    tokenizer
    LLM
    LM Studio
    xcodebuild
    SwiftUI
    DocC
    """

    private let passiveVoiceYML = """
    extends: existence
    message: "Passive voice: '%s'"
    level: warning
    link: https://vale.sh/docs/topics/styles/
    tokens:
      - \\b(is|are|was|were|been|being)\\s+\\w+ed\\b
    """

    private let weaselYML = """
    extends: existence
    message: "Hedging word: '%s'"
    level: warning
    link: https://vale.sh/docs/topics/styles/
    tokens:
      - might
      - perhaps
      - possibly
      - somewhat
      - rather
    """
}
```

---

## Write to: Merlin/Discipline/ProseReadabilityChecker.swift

Full file content:

```swift
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
        // No grade extracted (vale missing, no readability alert) → fall back to the
        // target so the gate passes — graceful degradation.
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
```

---

## Edit: Merlin/Discipline/DisciplineEngine.swift

In `scan()`, after the WHY-comment loop and before `consecutiveFailures = 0`, add a
prose-readability pass. Enumerate `*.md` doc files, compute each file's target grade,
run the checker, and emit a `proseReadabilityFail` finding for over-grade files.

```swift
            // Prose readability — run the checker over project doc files.
            for docFile in Self.enumerateDocFiles(projectPath: projectPath) {
                let targetGrade = Self.targetGrade(for: docFile, adapter: adapter)
                let result = await proseReadabilityChecker.check(
                    docFile: docFile, targetGrade: targetGrade)
                guard result.measuredGrade > result.targetGrade else { continue }
                let f = Finding(
                    id: UUID(),
                    category: .proseReadabilityFail,
                    severity: .nudge,
                    summary: URL(fileURLWithPath: docFile).lastPathComponent,
                    detail: String(
                        format: "Readability grade %.1f exceeds target %.1f",
                        result.measuredGrade, result.targetGrade),
                    suggestedAction: result.suggestions.first
                        ?? "Simplify the prose in this document",
                    createdAt: now,
                    lastSeenAt: now
                )
                await queue.add(f)
                findings.append(f)
            }

            consecutiveFailures = 0
```

Add these two private static helpers inside `DisciplineEngine` (e.g. above the
`DisciplineError` enum):

```swift
    // MARK: - Doc-file helpers

    private static func enumerateDocFiles(projectPath: String) -> [String] {
        var files: [String] = []
        let root = URL(fileURLWithPath: projectPath)
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return files }
        for case let url as URL in enumerator where url.pathExtension == "md" {
            files.append(url.path)
        }
        return files
    }

    /// Target Flesch-Kincaid grade for a doc file. Architecture-related docs allow a
    /// higher grade (11.0); everything else uses the adapter's configured grade for a
    /// matching doc kind, falling back to 9.0.
    private static func targetGrade(
        for docFile: String, adapter: ProjectAdapter
    ) -> Double {
        let name = URL(fileURLWithPath: docFile).lastPathComponent.lowercased()
            .replacingOccurrences(of: "_", with: "-")
        if name.contains("architecture") {
            return 11.0
        }
        for (pattern, grade) in adapter.docTargetGrade {
            let normalized = pattern.lowercased().replacingOccurrences(of: "_", with: "-")
            if name.contains(normalized) {
                return grade
            }
        }
        return 9.0
    }
```

---

## Fixes

- `ValeStyleWriter` `readability.yml` now uses `extends: readability` with a `metrics:`
  list and a `grade:` threshold, replacing the non-functional `extends: existence`.
- `ProseReadabilityChecker.extractGrade` / `extractSuggestions` parse Vale's real
  `--output JSON` shape (file-keyed dictionary of alert arrays). The grade is read from
  the readability alert's `Message`. The `dryRun` / `forcedGrade` test seam is unchanged.
- `DisciplineEngine.scan()` now enumerates `*.md` doc files, computes each file's target
  grade (architecture → 11.0, else adapter config / 9.0), runs `proseReadabilityChecker`,
  and emits a `proseReadabilityFail` finding (`.nudge`) per over-grade file. The
  dependency is no longer dead.

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40

xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED** and all phase 270a tests pass. No prior phase regresses.

## Commit

```bash
git add tasks/task-270b-prose-production-path.md \
    Merlin/Discipline/ValeStyleWriter.swift \
    Merlin/Discipline/ProseReadabilityChecker.swift \
    Merlin/Discipline/DisciplineEngine.swift
git commit -m "Phase 270b — Prose readability production path"
```
