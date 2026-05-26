# Task 249b — ManualCoverageScanner

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 249a complete: failing tests for the real ManualCoverageScanner implementation.

Replaces the stub in `Merlin/Discipline/ManualCoverageScanner.swift` with the real scanner.

---

## Edit

### Merlin/Discipline/ManualCoverageScanner.swift (replace stub with full implementation)

```swift
import Foundation

struct ManualCoverageGap: Sendable {
    let surface: String
    let surfaceType: String
    let firstSeen: Date
    let suggestedSection: String?
}

/// Scans source files for user-facing surfaces and doc files for coverage blocks.
/// Returns gaps where surfaces are not covered.
actor ManualCoverageScanner {

    // MARK: - Public API

    func scan(projectPath: String, adapter: ProjectAdapter) async -> [ManualCoverageGap] {
        let surfaces = enumerateSurfaces(projectPath: projectPath, adapter: adapter)
        let covered = buildCoveredSet(projectPath: projectPath)

        var gaps: [ManualCoverageGap] = []
        let now = Date()
        for (surface, surfaceType) in surfaces where !covered.contains(surface) {
            gaps.append(ManualCoverageGap(
                surface: surface,
                surfaceType: surfaceType,
                firstSeen: now,
                suggestedSection: nil
            ))
        }
        return gaps
    }

    /// Returns a map from covered surface identifier to doc files that cover it.
    func buildCoverageMap(
        projectPath: String,
        adapter: ProjectAdapter
    ) async -> [String: [String]] {
        var map: [String: [String]] = [:]
        let docFiles = enumerateDocFiles(projectPath: projectPath)
        for docFile in docFiles {
            guard let text = try? String(contentsOf: URL(fileURLWithPath: docFile),
                                         encoding: .utf8) else { continue }
            for surface in extractCoversBlock(from: text) {
                map[surface, default: []].append(docFile)
            }
        }
        return map
    }

    // MARK: - Surface enumeration

    private func enumerateSurfaces(
        projectPath: String,
        adapter: ProjectAdapter
    ) -> [(surface: String, type: String)] {
        var results: [(String, String)] = []
        let root = URL(fileURLWithPath: projectPath)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return results }

        for case let url as URL in enumerator {
            guard url.pathExtension == "swift",
                  !url.path.contains("Tests/"),
                  !url.path.contains("/tasks/"),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lines = text.components(separatedBy: .newlines)
            for (idx, line) in lines.enumerated() {
                // Check for not-user-facing annotation on the preceding line
                if idx > 0 && lines[idx - 1].contains("manual: not-user-facing") { continue }
                if line.contains("manual: not-user-facing") { continue }

                for pattern in adapter.manualCoveragePatterns {
                    guard line.range(of: pattern.regex, options: .regularExpression) != nil
                    else { continue }
                    let surface = extractSurface(from: line, pattern: pattern)
                    if !surface.isEmpty {
                        results.append((surface, pattern.type))
                    }
                }
            }
        }
        return results
    }

    private func extractSurface(from line: String, pattern: ManualCoveragePattern) -> String {
        // Extract the matched substring as the surface identifier
        guard let range = line.range(of: pattern.regex, options: .regularExpression) else {
            return ""
        }
        let matched = String(line[range])
        // Include nearby quoted string if present (e.g. register("name"))
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if let q1 = trimmed.range(of: "\""),
           let q2 = trimmed.range(of: "\"", range: q1.upperBound..<trimmed.endIndex) {
            let name = String(trimmed[q1.upperBound..<q2.lowerBound])
            return "\(matched)(\"\(name)\")"
        }
        return matched
    }

    // MARK: - Coverage-block parsing

    private func buildCoveredSet(projectPath: String) -> Set<String> {
        var covered = Set<String>()
        for docFile in enumerateDocFiles(projectPath: projectPath) {
            guard let text = try? String(contentsOf: URL(fileURLWithPath: docFile),
                                         encoding: .utf8) else { continue }
            for surface in extractCoversBlock(from: text) {
                covered.insert(surface)
            }
        }
        return covered
    }

    private func extractCoversBlock(from text: String) -> [String] {
        var results: [String] = []
        var inBlock = false
        for line in text.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t == "<!-- covers:" || t.hasPrefix("<!-- covers:") {
                inBlock = true; continue
            }
            if inBlock {
                if t == "-->" { inBlock = false; continue }
                let surface = t.trimmingCharacters(in: CharacterSet(charactersIn: "- "))
                if !surface.isEmpty { results.append(surface) }
            }
        }
        return results
    }

    private func enumerateDocFiles(projectPath: String) -> [String] {
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

Expected: **BUILD SUCCEEDED** and all task 249a tests pass. No prior task regresses.

## Commit

```bash
git add tasks/task-249b-manual-coverage-scanner.md \
    Merlin/Discipline/ManualCoverageScanner.swift
git commit -m "Task 249b — ManualCoverageScanner (full implementation replaces stub)"
```
