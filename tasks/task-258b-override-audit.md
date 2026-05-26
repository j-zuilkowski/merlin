# Task 258b — Override Audit Log

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 258a complete: failing tests for OverrideAuditLog and OverrideEntry.

---

## Write to

### Merlin/Discipline/OverrideAuditLog.swift (new file)

```swift
import Foundation

/// An individual override event appended to `.merlin/override-log.jsonl`.
struct OverrideEntry: Sendable, Codable {
    let timestamp: Date
    let category: String
    let file: String
    let line: Int
    let rationale: String
    let userDismissed: Bool
    let viaAnnotation: Bool
    let annotationText: String?
}

/// Persists override events to a JSONL file and runs weekly review.
actor OverrideAuditLog {

    private let logPath: String

    /// Threshold: more than this many overrides per category in 7 days triggers a finding.
    private let weeklyThreshold = 5

    init(logPath: String) {
        self.logPath = logPath
    }

    // MARK: - API

    func record(_ entry: OverrideEntry) async throws {
        let data = try JSONEncoder().encode(entry)
        guard let line = String(data: data, encoding: .utf8) else { return }
        let url = URL(fileURLWithPath: logPath)
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent, withIntermediateDirectories: true, attributes: nil)

        if FileManager.default.fileExists(atPath: logPath) {
            let handle = try FileHandle(forWritingTo: url)
            handle.seekToEndOfFile()
            handle.write((line + "\n").data(using: .utf8)!)
            handle.closeFile()
        } else {
            try (line + "\n").write(to: url, atomically: true, encoding: .utf8)
        }

        TelemetryEmitter.shared.emit("discipline.override.recorded",
            data: ["category": entry.category, "file": entry.file,
                   "line": entry.line, "rationale": entry.rationale])
    }

    func entries(since date: Date) async -> [OverrideEntry] {
        loadAll().filter { $0.timestamp >= date }
    }

    func weeklyReview(queue: PendingAttentionQueue) async {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        let recent = loadAll().filter { $0.timestamp >= cutoff }

        // Count per category
        var counts: [String: Int] = [:]
        for e in recent { counts[e.category, default: 0] += 1 }

        for (category, count) in counts where count > weeklyThreshold {
            let now = Date()
            let f = Finding(
                id: UUID(),
                category: .overrideAuditAccumulation,
                severity: .nudge,
                summary: "\(count) overrides in '\(category)' this week",
                detail: "You've used '\(category)' overrides \(count) times in the past 7 days. " +
                        "Is the trigger list too aggressive, or are you cutting corners?",
                suggestedAction: "Review override-log.jsonl or relax the trigger via adapter config",
                createdAt: now,
                lastSeenAt: now
            )
            await queue.add(f)
            TelemetryEmitter.shared.emit("discipline.override-audit",
                data: ["category": category, "count": count, "threshold": weeklyThreshold])
        }
    }

    // MARK: - Persistence

    private func loadAll() -> [OverrideEntry] {
        guard let text = try? String(contentsOfFile: logPath, encoding: .utf8) else { return [] }
        return text.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .compactMap { line in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode(OverrideEntry.self, from: data)
            }
    }
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

Expected: **BUILD SUCCEEDED** and all task 258a tests pass. No prior task regresses.

## Commit

```bash
git add tasks/task-258b-override-audit.md \
    Merlin/Discipline/OverrideAuditLog.swift
git commit -m "Task 258b — OverrideAuditLog + OverrideEntry + weekly review event"
```
