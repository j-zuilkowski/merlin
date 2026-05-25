# Task 257b — Vale Pre-Commit Gate

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 257a complete: failing tests for ProseGate and ProseGateResult.

---

## Write to

### Merlin/Discipline/ProseGate.swift (new file)

```swift
import Foundation

/// Result of the Vale prose pre-commit gate check.
enum ProseGateResult: Sendable {
    case pass
    case block(findings: [ReadabilityFinding])
}

/// Runs `ProseReadabilityChecker` over changed doc files and blocks if any exceed
/// their target grade.
actor ProseGate {

    // MARK: - Checker factory (injectable for tests)

    typealias CheckerFactory = @Sendable (String, Double) -> ProseReadabilityChecker

    private let checkerFactory: CheckerFactory

    init(checkerFactory: CheckerFactory? = nil) {
        if let factory = checkerFactory {
            self.checkerFactory = factory
        } else {
            self.checkerFactory = { _, _ in ProseReadabilityChecker() }
        }
    }

    // MARK: - API

    func check(
        changedDocFiles: [String],
        adapter: ProjectAdapter
    ) async -> ProseGateResult {
        guard !changedDocFiles.isEmpty else { return .pass }

        var failures: [ReadabilityFinding] = []

        await withTaskGroup(of: ReadabilityFinding?.self) { group in
            for docFile in changedDocFiles {
                let target = resolveTargetGrade(for: docFile, adapter: adapter)
                let checker = checkerFactory(docFile, target)
                group.addTask {
                    let finding = await checker.check(docFile: docFile, targetGrade: target)
                    return finding.measuredGrade > finding.targetGrade ? finding : nil
                }
            }
            for await result in group {
                if let finding = result {
                    failures.append(finding)
                }
            }
        }

        if failures.isEmpty { return .pass }
        return .block(findings: failures)
    }

    // MARK: - Grade resolution

    private func resolveTargetGrade(
        for docFile: String,
        adapter: ProjectAdapter
    ) -> Double {
        let filename = URL(fileURLWithPath: docFile)
            .deletingPathExtension()
            .lastPathComponent
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")

        // Match adapter grade keys against filename fragments
        for (key, grade) in adapter.docTargetGrade {
            let normKey = key.lowercased().replacingOccurrences(of: "-", with: "_")
            if filename.contains(normKey) { return grade }
        }
        return 9.0 // Conservative default
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

Expected: **BUILD SUCCEEDED** and all task 257a tests pass. No prior task regresses.

## Commit

```bash
git add tasks/task-257b-vale-gate.md \
    Merlin/Discipline/ProseGate.swift
git commit -m "Task 257b — Vale pre-commit gate + critic Stage 2 prose check"
```
