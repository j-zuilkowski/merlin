# Phase 256b — ProseReadabilityChecker

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 256a complete: failing tests for ProseReadabilityChecker and ValeStyleWriter.

Replaces the stub in `Merlin/Discipline/ProseReadabilityChecker.swift` and adds
`ValeStyleWriter`.

---

## Edit

### Merlin/Discipline/ProseReadabilityChecker.swift (replace stub with full implementation)

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

    // MARK: - Vale runner

    private func runVale(docFile: String, targetGrade: Double) async -> ReadabilityFinding {
        // vale --output JSON <docFile>
        let valeOutput = await spawnVale(docFile: docFile)
        let grade = extractGrade(from: valeOutput) ?? targetGrade
        let suggestions = grade > targetGrade
            ? extractSuggestions(from: valeOutput)
            : []
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
            try? process.run()
        }
    }

    private func extractGrade(from json: String) -> Double? {
        // Vale JSON: look for "ReadabilityScore" or similar field
        if let data = json.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let score = obj["readability"] as? Double {
            return score
        }
        return nil
    }

    private func extractSuggestions(from json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return arr.compactMap { $0["Message"] as? String }
    }
}
```

### Merlin/Discipline/ValeStyleWriter.swift (new file)

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

    // MARK: - Style file content

    private let readabilityYML = """
    extends: existence
    message: "Readability grade (%s) exceeds target."
    level: warning
    link: https://vale.sh/docs/topics/styles/
    tokens:
      - Flesch-Kincaid
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

Expected: **BUILD SUCCEEDED** and all phase 256a tests pass. No prior phase regresses.

## Commit

```bash
git add tasks/task-256b-prose-readability.md \
    Merlin/Discipline/ProseReadabilityChecker.swift \
    Merlin/Discipline/ValeStyleWriter.swift
git commit -m "Phase 256b — ProseReadabilityChecker (Vale integration) + ValeStyleWriter"
```
