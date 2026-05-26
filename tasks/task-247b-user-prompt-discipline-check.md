# Task 247b — UserPromptSubmit Discipline Check

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 247a complete: failing tests for UserPromptDisciplineChecker and UserPromptCheckResult.

---

## Write to

### Merlin/Discipline/UserPromptDisciplineChecker.swift (new file)

```swift
import Foundation

/// Result of a user-prompt discipline check.
enum UserPromptCheckResult: Sendable {
    /// Prompt does not appear to be a new feature request, or a matching task file exists.
    case ok
    /// Prompt looks like a feature request but no NNa task file was found.
    case missingTaskFile(suggestion: String)
}

/// Checks incoming user prompts for unscoped feature requests.
/// Returns `.missingTaskFile` when the prompt describes a new feature that has no
/// corresponding NNa task file in `tasks/`.
actor UserPromptDisciplineChecker {

    // MARK: - Feature-request keywords

    private let featureVerbs: Set<String> = [
        "add", "implement", "build", "create", "write", "introduce",
        "develop", "make", "design", "support"
    ]

    private let nonFeatureIndicators: Set<String> = [
        "fix", "typo", "bug", "crash", "error", "broken", "regression",
        "revert", "refactor", "rename", "move", "delete", "remove"
    ]

    // MARK: - Public API

    func check(prompt: String, projectPath: String) async -> UserPromptCheckResult {
        let lower = prompt.lowercased()
        let words = lower.components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }

        // Non-feature-request early exit
        if words.contains(where: { nonFeatureIndicators.contains($0) }) {
            return .ok
        }

        // Feature-request detection
        guard words.contains(where: { featureVerbs.contains($0) }) else {
            return .ok
        }

        // Extract candidate noun (first capitalised word-ish token from original)
        let candidates = extractCandidateNouns(from: prompt)

        // Check whether any NNa task file mentions a candidate noun
        if candidates.isEmpty || candidatesHaveMatchingTask(candidates, projectPath: projectPath) {
            return .ok
        }

        let suggestion = "Write a task NNa file before implementing: /project:task"
        return .missingTaskFile(suggestion: suggestion)
    }

    // MARK: - Helpers

    private func extractCandidateNouns(from prompt: String) -> [String] {
        // Look for PascalCase or multi-word feature names
        let words = prompt.components(separatedBy: .whitespaces)
        return words.filter { word in
            let clean = word.trimmingCharacters(in: .punctuationCharacters)
            return clean.count > 3 && clean.first?.isUppercase == true
        }
    }

    private func candidatesHaveMatchingTask(
        _ candidates: [String], projectPath: String
    ) -> Bool {
        let tasksDir = URL(fileURLWithPath: projectPath).appendingPathComponent(" tasks")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: tasksDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return false }

        // NNa files only
        let nnAFiles = files.filter { file in
            file.pathExtension == "md" &&
            file.lastPathComponent.range(of: #"task-\d+a-"#,
                                         options: .regularExpression) != nil
        }

        for candidate in candidates {
            let lower = candidate.lowercased()
            for file in nnAFiles {
                if file.lastPathComponent.lowercased().contains(lower) { return true }
                if let text = try? String(contentsOf: file, encoding: .utf8),
                   text.lowercased().contains(lower) {
                    return true
                }
            }
        }
        return false
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

Expected: **BUILD SUCCEEDED** and all task 247a tests pass. No prior task regresses.

## Commit

```bash
git add tasks/task-247b-user-prompt-discipline-check.md \
    Merlin/Discipline/UserPromptDisciplineChecker.swift
git commit -m "Task 247b — UserPromptSubmit discipline check for unscoped feature requests"
```
