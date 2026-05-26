# Task 309b — ReachabilityScanner (implementation)

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

> **Note:** `injectedTypes` and the per-line loop here are refined by task 317b
> (annotation-based injection detection, comment-line skip). Implement 317b's version.

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Task 309a complete: failing tests in `ReachabilityScannerTests`.

`ReachabilityScanner` is a peer of `TargetGateScanner` / `StubMarkerScanner`. Pure
Foundation — lands in `Merlin/Discipline/` (compiled into both the app and the
`merlin-discipline` CLI), so no SwiftUI/AppKit imports. Its checks are heuristics
surfaced as advisory `nudge` findings, not blocking gates.

---

## 1. Write to: Merlin/Discipline/ReachabilityScanner.swift

```swift
import Foundation

/// One component that compiles green but is never reached.
struct UnwiredComponentFinding: Sendable, Equatable {
    let symbol: String
    let file: String
    /// "view-never-instantiated" | "environment-object-not-injected"
    let kind: String
    let detail: String
}

/// Heuristic reachability analysis over the Swift sources of a project.
///
/// Catches two unwired-component classes a green build cannot: a SwiftUI `View`
/// referenced by no other source, and a type consumed via `@EnvironmentObject` that is
/// never injected. Findings are advisory — heuristics, not proofs.
actor ReachabilityScanner {

    func scan(projectPath: String) async -> [UnwiredComponentFinding] {
        var sources: [(path: String, lines: [String])] = []
        for url in swiftFiles(projectPath: projectPath) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            sources.append((url.path, text.components(separatedBy: .newlines)))
        }
        guard !sources.isEmpty else { return [] }

        // Global identifier frequency across every scanned source line.
        var frequency: [String: Int] = [:]
        let idRegex = try? NSRegularExpression(pattern: #"[A-Za-z_][A-Za-z0-9_]*"#)
        for source in sources {
            for line in source.lines {
                let ns = line as NSString
                idRegex?.enumerateMatches(
                    in: line, range: NSRange(location: 0, length: ns.length)
                ) { match, _, _ in
                    guard let match, let r = Range(match.range, in: line) else { return }
                    frequency[String(line[r]), default: 0] += 1
                }
            }
        }

        var findings: [UnwiredComponentFinding] = []
        var envConsumed: [(type: String, file: String)] = []
        var injectedTypeNames: Set<String> = []

        for source in sources {
            for line in source.lines {
                if let view = declaredViewName(in: line), (frequency[view] ?? 0) <= 1 {
                    findings.append(UnwiredComponentFinding(
                        symbol: view, file: source.path,
                        kind: "view-never-instantiated",
                        detail: "SwiftUI View '\(view)' is declared but referenced by "
                            + "no other non-test source — it is in no view hierarchy."))
                }
                if let type = environmentObjectType(in: line) {
                    envConsumed.append((type, source.path))
                }
                injectedTypeNames.formUnion(injectedTypes(in: line))
            }
        }

        for consumer in envConsumed where !injectedTypeNames.contains(consumer.type) {
            findings.append(UnwiredComponentFinding(
                symbol: consumer.type, file: consumer.file,
                kind: "environment-object-not-injected",
                detail: "Type '\(consumer.type)' is consumed via @EnvironmentObject but "
                    + "is never created or passed to .environmentObject() anywhere — "
                    + "views using it crash at runtime."))
        }
        return findings
    }

    // MARK: - File enumeration

    private func swiftFiles(projectPath: String) -> [URL] {
        var files: [URL] = []
        let root = URL(fileURLWithPath: projectPath)
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]) else { return files }
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  !url.path.contains("Tests/"),
                  !url.path.contains("/.build/") else { continue }
            files.append(url)
        }
        return files
    }

    // MARK: - Line heuristics

    /// The type name of a single-line `struct`/`class` declaration that conforms to
    /// `View`, excluding app entry points and `#Preview` providers.
    private func declaredViewName(in line: String) -> String? {
        let pattern = #"^\s*(?:public\s+|internal\s+|fileprivate\s+)?(?:final\s+)?(?:struct|class)\s+([A-Z][A-Za-z0-9_]*)\s*:\s*([^{]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(
                in: line, range: NSRange(line.startIndex..., in: line)),
              let nameR = Range(m.range(at: 1), in: line),
              let confR = Range(m.range(at: 2), in: line) else { return nil }
        let name = String(line[nameR])
        let conformances = String(line[confR])
        guard conformances.range(of: #"\bView\b"#, options: .regularExpression) != nil,
              !name.hasSuffix("_Previews"),
              conformances.range(
                of: #"\b(App|Scene|PreviewProvider)\b"#,
                options: .regularExpression) == nil
        else { return nil }
        return name
    }

    /// The declared type of an `@EnvironmentObject var x: T` property.
    private func environmentObjectType(in line: String) -> String? {
        let pattern = #"@EnvironmentObject\s+(?:(?:private|public|internal|fileprivate)\s+)?var\s+\w+\s*:\s*([A-Z][A-Za-z0-9_]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(
                in: line, range: NSRange(line.startIndex..., in: line)),
              let r = Range(m.range(at: 1), in: line) else { return nil }
        return String(line[r])
    }

    /// Type names constructed on an injection-relevant line — a `.environmentObject(...)`
    /// call or a `@StateObject`/`@ObservedObject` property. Approximates "this type is
    /// created and provided to the environment somewhere".
    private func injectedTypes(in line: String) -> [String] {
        guard line.contains(".environmentObject(")
            || line.contains("@StateObject")
            || line.contains("@ObservedObject") else { return [] }
        var types: [String] = []
        let pattern = #"\b([A-Z][A-Za-z0-9_]*)\s*\("#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let ns = line as NSString
            for m in regex.matches(
                in: line, range: NSRange(location: 0, length: ns.length)) {
                if let r = Range(m.range(at: 1), in: line) {
                    types.append(String(line[r]))
                }
            }
        }
        return types
    }
}
```

## 2. Edit: Merlin/Discipline/Finding.swift
Add `case unwiredComponent` to `FindingCategory` (after `stubbedImplementation`).
**Then update `MerlinTests/Unit/FindingModelTests.swift`** — add
`XCTAssertEqual(FindingCategory.unwiredComponent.rawValue, "unwiredComponent")` and
adjust any `allCases.count` assertion.

## 3. Edit: Merlin/Discipline/DisciplineEngine.swift
Same wiring pattern as  tasks 307b / 308b:

- **Stored property:** `private let reachabilityScanner: ReachabilityScanner`
- **Init parameter** (defaulted) — insert after `stubMarkerScanner:`:
  ```swift
        stubMarkerScanner: StubMarkerScanner = StubMarkerScanner(),
        reachabilityScanner: ReachabilityScanner = ReachabilityScanner(),
        storePath: String,
  ```
  and `self.reachabilityScanner = reachabilityScanner` in the body.
- **In `scan(projectPath:)`** add the parallel scan and extend the tuple await:
  ```swift
  async let unwiredComponents = reachabilityScanner.scan(projectPath: projectPath)
  ```
  ```swift
  let (drift, gaps, refs, why, ungated, stubs, unwired) = await (
      driftFindings, coverageGaps, docRefs, whyTriggers,
      ungatedTargets, stubMarkers, unwiredComponents)
  ```
- **Conversion block** — after the stub-markers block:
  ```swift
  // Unwired components — code that compiles green but is never reached.
  for component in unwired {
      let f = Finding(
          id: UUID(),
          category: .unwiredComponent,
          severity: .nudge,
          summary: component.symbol,
          detail: component.detail,
          suggestedAction: "Wire this component into the app, or delete it if obsolete.",
          createdAt: now,
          lastSeenAt: now)
      await queue.add(f)
      findings.append(f)
  }
  ```

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/ReachabilityScannerTests -only-testing:MerlinTests/FindingModelTests 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|error:'
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|warning:|BUILD (SUCCEEDED|FAILED)'
```
Expected: `ReachabilityScannerTests` and `FindingModelTests` pass; BUILD SUCCEEDED, zero
warnings.

## Commit
```
git add Merlin/Discipline/ReachabilityScanner.swift Merlin/Discipline/Finding.swift \
  Merlin/Discipline/DisciplineEngine.swift MerlinTests/Unit/FindingModelTests.swift \
  tasks/task-309b-reachability-scanner.md
git commit -m "Task 309b — ReachabilityScanner: flag unwired views and uninjected env objects"
```
