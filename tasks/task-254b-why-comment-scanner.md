# Task 254b — WhyCommentScanner

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 254a complete: failing tests for the real WhyCommentScanner.

Replaces the stub in `Merlin/Discipline/WhyCommentScanner.swift`.

---

## Edit

### Merlin/Discipline/WhyCommentScanner.swift (replace stub with full implementation)

```swift
import Foundation

struct WhyCommentTrigger: Sendable {
    let pattern: String
    let reason: String
    let file: String
    let line: Int
    let context: String        // ±2 lines
    let hasNearbyComment: Bool
}

/// Scans source files for adapter-defined WHY-trigger patterns and checks for
/// nearby explanatory comments.
actor WhyCommentScanner {

    // MARK: - Public API

    func scan(projectPath: String, adapter: ProjectAdapter) async -> [WhyCommentTrigger] {
        guard !adapter.whyCommentTriggers.isEmpty else { return [] }
        var results: [WhyCommentTrigger] = []

        let root = URL(fileURLWithPath: projectPath)
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return results }

        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" || url.pathExtension == "rs",
                  !url.path.contains("Tests/"),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lines = text.components(separatedBy: .newlines)
            for triggerSpec in adapter.whyCommentTriggers {
                results.append(contentsOf: scanLines(
                    lines, file: url.path, spec: triggerSpec))
            }
        }
        return results
    }

    // MARK: - Per-file scan

    private func scanLines(
        _ lines: [String],
        file: String,
        spec: WHYTriggerSpec
    ) -> [WhyCommentTrigger] {
        var results: [WhyCommentTrigger] = []
        for (idx, line) in lines.enumerated() {
            guard line.range(of: spec.regex, options: .regularExpression) != nil else { continue }

            // Suppression annotation on the same line
            if line.contains("rationale-not-needed:") { continue }

            // Context window: ±2 lines
            let windowStart = max(0, idx - 2)
            let windowEnd   = min(lines.count - 1, idx + 2)
            let window = lines[windowStart...windowEnd]
            let contextStr = window.joined(separator: "\n")

            // Check for explanatory comment in ±3 lines
            let commentWindow = lines[max(0, idx - 3)...min(lines.count - 1, idx + 3)]
            let hasComment = commentWindow.contains { commentLine in
                let t = commentLine.trimmingCharacters(in: .whitespaces)
                return (t.hasPrefix("//") || t.hasPrefix("#") || t.hasPrefix("/*")) &&
                       !t.contains("rationale-not-needed:")
            }

            results.append(WhyCommentTrigger(
                pattern: spec.regex,
                reason: spec.reason,
                file: file,
                line: idx + 1,
                context: contextStr,
                hasNearbyComment: hasComment
            ))
        }
        return results
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

Expected: **BUILD SUCCEEDED** and all task 254a tests pass. No prior task regresses.

## Commit

```bash
git add tasks/task-254b-why-comment-scanner.md \
    Merlin/Discipline/WhyCommentScanner.swift
git commit -m "Task 254b — WhyCommentScanner real implementation + rationale-not-needed annotation"
```
