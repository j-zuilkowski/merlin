# Phase 255b — WHY-Comment Pre-Commit Hook

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 255a complete: failing tests for WHYCommentGate, WHYGateResult, OverrideAnnotationParser.

---

## Write to

### Merlin/Discipline/WHYCommentGate.swift (new file)

```swift
import Foundation

/// Result of the WHY-comment pre-commit gate check.
enum WHYGateResult: Sendable {
    case pass
    case block(violations: [WhyCommentTrigger])
}

/// Runs the WHY-comment scanner and applies the gate: any trigger without a nearby comment
/// and without a `rationale-not-needed:` annotation causes a block.
actor WHYCommentGate {

    func check(
        projectPath: String,
        adapter: ProjectAdapter
    ) async -> WHYGateResult {
        let scanner = WhyCommentScanner()
        let triggers = await scanner.scan(projectPath: projectPath, adapter: adapter)
        let violations = triggers.filter { !$0.hasNearbyComment }
        if violations.isEmpty {
            return .pass
        }
        return .block(violations: violations)
    }
}
```

### Merlin/Discipline/OverrideAnnotationParser.swift (new file)

```swift
import Foundation

/// An inline `rationale-not-needed:` annotation parsed from a source line.
struct OverrideAnnotation: Sendable {
    let rationale: String
}

/// Parses `// rationale-not-needed: <reason>` annotations from source lines.
struct OverrideAnnotationParser: Sendable {

    private let marker = "rationale-not-needed:"

    func parse(line: String) -> OverrideAnnotation? {
        guard let range = line.range(of: marker) else { return nil }
        let rationale = String(line[range.upperBound...])
            .trimmingCharacters(in: .whitespaces)
        guard !rationale.isEmpty else { return nil }
        return OverrideAnnotation(rationale: rationale)
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

Expected: **BUILD SUCCEEDED** and all phase 255a tests pass. No prior phase regresses.

## Commit

```bash
git add tasks/task-255b-why-comment-hook.md \
    Merlin/Discipline/WHYCommentGate.swift \
    Merlin/Discipline/OverrideAnnotationParser.swift
git commit -m "Phase 255b — WHY-comment pre-commit gate + OverrideAnnotationParser"
```
