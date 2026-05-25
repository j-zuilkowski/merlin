# Phase 331b — Discipline Exclusions Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 331a complete: failing `DisciplineExclusionsTests` in place.

This phase adds `DisciplineExclusions` — a shared directory blacklist — and wires its
`isExcluded(_:)` predicate into **every** file-walking discipline scanner so the
`merlin-eval/` tree (moved into the repo in phase 332) is never scanned.

There is no shared file-discovery utility — each scanner rolls its own
`FileManager.enumerator`. So `isExcluded` is applied at **10 enumeration sites across 8
files**. `TargetGateScanner` is *not* touched: it only parses `project.yml` and never
walks files.

---

## Write to: Merlin/Discipline/DisciplineExclusions.swift

```swift
import Foundation

/// The directory blacklist every file-walking discipline scanner honours.
///
/// `merlin-eval/` holds the eval suite's fixtures — deliberately-buggy fixture source
/// and scenario Markdown. Scanning it raises false drift / unwired / stub / dangling-
/// reference findings, so every scanner skips any file beneath an excluded directory.
enum DisciplineExclusions {

    /// Directory names that exclude every file at or beneath them. Matched as a path
    /// *component*, not a substring, so a file merely named `merlin-eval-x` is unaffected.
    static let excludedDirectoryNames: Set<String> = ["merlin-eval"]

    /// True when `url` lies inside a blacklisted directory.
    static func isExcluded(_ url: URL) -> Bool {
        url.pathComponents.contains { excludedDirectoryNames.contains($0) }
    }
}
```

---

## Edit — wire `isExcluded` into all 10 enumeration sites

Each edit adds the predicate alongside the scanner's existing exclusion logic. Apply
each exactly; the surrounding lines are shown for an unambiguous match.

### 1. `Merlin/Discipline/TaskScanner.swift` — `enumerateSourceDeclarations`
old:
```swift
            if url.path.contains("/tasks/") { continue }
            if url.pathComponents.contains(where: { $0.hasSuffix("Tests") }) { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
```
new:
```swift
            if url.path.contains("/tasks/") { continue }
            if url.pathComponents.contains(where: { $0.hasSuffix("Tests") }) { continue }
            if DisciplineExclusions.isExcluded(url) { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
```

### 2. `Merlin/Discipline/ReachabilityScanner.swift` — `swiftFiles`
old:
```swift
            guard url.pathExtension == "swift",
                  !url.path.contains("Tests/"),
                  !url.path.contains("/.build/"),
                  !url.path.contains("/build/"),
                  !url.path.contains("/DerivedData/") else { continue }
```
new:
```swift
            guard url.pathExtension == "swift",
                  !url.path.contains("Tests/"),
                  !url.path.contains("/.build/"),
                  !url.path.contains("/build/"),
                  !url.path.contains("/DerivedData/"),
                  !DisciplineExclusions.isExcluded(url) else { continue }
```

### 3. `Merlin/Discipline/StubMarkerScanner.swift` — `scan`
old:
```swift
                  !url.path.contains("/DerivedData/"),
                  // The scanner's own marker table embeds the marker vocabulary.
                  url.lastPathComponent != "StubMarkerScanner.swift",
```
new:
```swift
                  !url.path.contains("/DerivedData/"),
                  !DisciplineExclusions.isExcluded(url),
                  // The scanner's own marker table embeds the marker vocabulary.
                  url.lastPathComponent != "StubMarkerScanner.swift",
```

### 4. `Merlin/Discipline/WhyCommentScanner.swift` — `scan`
old:
```swift
            guard (url.pathExtension == "swift" || url.pathExtension == "rs"),
                  !url.path.contains("Tests/"),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
```
new:
```swift
            guard (url.pathExtension == "swift" || url.pathExtension == "rs"),
                  !url.path.contains("Tests/"),
                  !DisciplineExclusions.isExcluded(url),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
```

### 5. `Merlin/Discipline/ManualCoverageScanner.swift` — `enumerateSurfaces`
old:
```swift
            guard url.pathExtension == "swift",
                  !url.path.contains("Tests/"),
                  !url.path.contains("/tasks/"),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
```
new:
```swift
            guard url.pathExtension == "swift",
                  !url.path.contains("Tests/"),
                  !url.path.contains("/tasks/"),
                  !DisciplineExclusions.isExcluded(url),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
```

### 6. `Merlin/Discipline/ManualCoverageScanner.swift` — `enumerateDocFiles`
old:
```swift
        for case let url as URL in enumerator where url.pathExtension == "md" {
            files.append(url.path)
        }
```
new:
```swift
        for case let url as URL in enumerator
        where url.pathExtension == "md" && !DisciplineExclusions.isExcluded(url) {
            files.append(url.path)
        }
```

### 7. `Merlin/Discipline/DocReferenceGraph.swift` — `enumerateSourceSymbols`
old:
```swift
            guard sourceExtensions.contains(url.pathExtension),
                  !p.contains("/build/"), !p.contains("/DerivedData/"),
                  !p.contains("/.build/"),
                  let text = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }
```
new:
```swift
            guard sourceExtensions.contains(url.pathExtension),
                  !p.contains("/build/"), !p.contains("/DerivedData/"),
                  !p.contains("/.build/"),
                  !DisciplineExclusions.isExcluded(url),
                  let text = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }
```

### 8. `Merlin/Discipline/DocReferenceGraph.swift` — `enumerateDocFiles`
old:
```swift
        for case let url as URL in enumerator where url.pathExtension == "md" {
            let p = url.path
            if p.contains("/build/") || p.contains("/DerivedData/")
                || p.contains("/.build/") { continue }
            files.append(p)
        }
```
new:
```swift
        for case let url as URL in enumerator where url.pathExtension == "md" {
            let p = url.path
            if p.contains("/build/") || p.contains("/DerivedData/")
                || p.contains("/.build/") || DisciplineExclusions.isExcluded(url) { continue }
            files.append(p)
        }
```

### 9. `Merlin/Discipline/DisciplineEngine.swift` — `enumerateDocFiles`
The text below is identical to site 8 but lives in `DisciplineEngine.swift` — edit it
there as well.
old:
```swift
        for case let url as URL in enumerator where url.pathExtension == "md" {
            let p = url.path
            if p.contains("/build/") || p.contains("/DerivedData/")
                || p.contains("/.build/") { continue }
            files.append(p)
        }
```
new:
```swift
        for case let url as URL in enumerator where url.pathExtension == "md" {
            let p = url.path
            if p.contains("/build/") || p.contains("/DerivedData/")
                || p.contains("/.build/") || DisciplineExclusions.isExcluded(url) { continue }
            files.append(p)
        }
```

### 10. `Merlin/Discipline/DisciplineCLI.swift` — `enumerateMarkdownDocs`
old:
```swift
        for case let url as URL in enumerator where url.pathExtension == "md" {
            docs.append(url.path)
        }
```
new:
```swift
        for case let url as URL in enumerator
        where url.pathExtension == "md" && !DisciplineExclusions.isExcluded(url) {
            docs.append(url.path)
        }
```

---

## Verify
```
cd ~/Documents/localProject/merlin
xcodegen generate
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/DisciplineExclusionsTests 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|error:|warning:'
xcodebuild -scheme MerlinTests-Live build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
# Wiring check — every file-walking scanner must reference the blacklist.
grep -l 'DisciplineExclusions.isExcluded' \
  Merlin/Discipline/TaskScanner.swift Merlin/Discipline/ReachabilityScanner.swift \
  Merlin/Discipline/StubMarkerScanner.swift Merlin/Discipline/WhyCommentScanner.swift \
  Merlin/Discipline/ManualCoverageScanner.swift Merlin/Discipline/DocReferenceGraph.swift \
  Merlin/Discipline/DisciplineEngine.swift Merlin/Discipline/DisciplineCLI.swift
```
Expected: both `build-for-testing` runs **BUILD SUCCEEDED** with zero warnings; all six
`DisciplineExclusionsTests` pass; the `grep -l` lists **all 8** files.

## Commit
```
git add Merlin/Discipline/DisciplineExclusions.swift \
        Merlin/Discipline/TaskScanner.swift Merlin/Discipline/ReachabilityScanner.swift \
        Merlin/Discipline/StubMarkerScanner.swift Merlin/Discipline/WhyCommentScanner.swift \
        Merlin/Discipline/ManualCoverageScanner.swift Merlin/Discipline/DocReferenceGraph.swift \
        Merlin/Discipline/DisciplineEngine.swift Merlin/Discipline/DisciplineCLI.swift \
        tasks/task-331b-discipline-exclusions.md
git commit -m "Phase 331b — DisciplineExclusions blacklist"
```
