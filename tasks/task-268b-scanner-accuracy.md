# Task 268b — Scanner Accuracy Fixes

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 268a complete: failing tests for the three scanner accuracy bugs.

This task fixes the test-file exclusion in `TaskScanner`, the comment/string-literal
false positives in `WhyCommentScanner`, and confirms the per-section reference
association in `DocReferenceGraph.build()`.

---

## Edit: Merlin/Discipline/TaskScanner.swift

In `enumerateSourceDeclarations(root:)`, replace the path filter. The current code skips
`"/Tests/"` (leading slash), which does not match `MerlinTests/`. Replace it with a
component-suffix check so any directory ending in `Tests` is excluded.

```swift
// Before:
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            let path = url.path
            if path.contains("/tasks/") || path.contains("/Tests/") {
                continue
            }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }

// After:
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            // Exclude task docs and any test target. The test directory is named
            // `MerlinTests` (also `MerlinLiveTests`, `MerlinE2ETests`), so a literal
            // "/Tests/" match misses it — check for a path component ending in "Tests".
            if url.path.contains("/tasks/") { continue }
            if url.pathComponents.contains(where: { $0.hasSuffix("Tests") }) { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
```

---

## Edit: Merlin/Discipline/WhyCommentScanner.swift

Replace the `scanLines` method so a trigger match is skipped when it falls inside a `//`
comment or a string literal on the same line.

```swift
    private func scanLines(
        _ lines: [String],
        file: String,
        spec: WHYTriggerSpec
    ) -> [WhyCommentTrigger] {
        var results: [WhyCommentTrigger] = []

        for (idx, line) in lines.enumerated() {
            guard let matchRange = line.range(
                of: spec.regex, options: .regularExpression) else { continue }
            if line.contains("rationale-not-needed:") { continue }
            // A trigger pattern that only appears inside a // comment or a string
            // literal is discussion, not code — skip it so the gate does not block
            // legitimate commits on false positives.
            if isInsideCommentOrString(line: line, matchStart: matchRange.lowerBound) {
                continue
            }

            let windowStart = max(0, idx - 2)
            let windowEnd = min(lines.count - 1, idx + 2)
            let contextStr = lines[windowStart...windowEnd].joined(separator: "\n")

            let commentStart = max(0, idx - 3)
            let commentEnd = min(lines.count - 1, idx + 3)
            let commentWindow = lines[commentStart...commentEnd]
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

    /// True when `matchStart` lies inside a `//` line comment or a `"..."` string
    /// literal on `line`.
    ///
    /// Heuristic, not a full lexer: it scans the prefix of the line up to the match.
    /// - If a `//` occurs before the match while not inside quotes, the match is in a
    ///   comment.
    /// - The count of unescaped `"` characters before the match: an odd count means
    ///   the match sits inside an open string literal.
    private func isInsideCommentOrString(line: String, matchStart: String.Index) -> Bool {
        var insideString = false
        var previous: Character?
        var index = line.startIndex
        while index < matchStart {
            let ch = line[index]
            if ch == "\"" && previous != "\\" {
                insideString.toggle()
            } else if ch == "/" && previous == "/" && !insideString {
                // A "//" reached before the match, outside any string → comment.
                return true
            }
            previous = ch
            index = line.index(after: index)
        }
        // If we ended the prefix scan still inside a string, the match is in a literal.
        return insideString
    }
```

The `scan(projectPath:adapter:)` method is unchanged.

---

## DocReferenceGraph.build() — section tracking

`DocReferenceGraph.build()` was already restructured to a single per-line pass in task
267b, so each reference is associated with the heading active at the line it appears on.
No further edit is needed here; `DocReferenceSectionTests` (task 268a) locks that
behaviour. This task does not modify `DocReferenceGraph.swift`.

---

## Fixes

- `TaskScanner.enumerateSourceDeclarations` now excludes any file whose path has a
  component ending in `Tests` (`MerlinTests`, `MerlinLiveTests`, `MerlinE2ETests`).
  Public test symbols no longer produce spurious `orange` "undocumented" findings.
- `WhyCommentScanner.scanLines` skips trigger matches inside `//` comments or string
  literals via the `isInsideCommentOrString` heuristic. Genuine bare triggers in
  executable code are still reported.
- `DocReferenceGraph.build()` per-section association is confirmed correct (fixed in
  267b); the regression test added in 268a guards it.

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

Expected: **BUILD SUCCEEDED** and all task 268a tests pass. No prior task regresses.

## Commit

```bash
git add tasks/task-268b-scanner-accuracy.md \
    Merlin/Discipline/TaskScanner.swift \
    Merlin/Discipline/WhyCommentScanner.swift
git commit -m "Task 268b — Scanner accuracy fixes"
```
