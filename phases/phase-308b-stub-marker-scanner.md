# Phase 308b — StubMarkerScanner (implementation)

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Phase 308a complete: failing tests in `StubMarkerScannerTests`.

`StubMarkerScanner` is a peer of `TargetGateScanner` (phase 307). Pure Foundation —
lands in `Merlin/Discipline/` (compiled into both the app and the `merlin-discipline`
CLI), so no SwiftUI/AppKit imports.

---

## 1. Write to: Merlin/Discipline/StubMarkerScanner.swift

```swift
import Foundation

/// One stub, placeholder, or deferred-work marker found in source.
struct StubMarkerFinding: Sendable, Equatable {
    let file: String
    let line: Int
    let marker: String
    /// True for code that aborts or does nothing if reached; false for deferral
    /// comments that merely flag future work.
    let isHardStub: Bool
    let context: String
}

/// Scans source for markers of unfinished work — code that compiles green but is not
/// actually done. Language-agnostic line scan over Swift and Rust sources.
actor StubMarkerScanner {

    private struct Marker { let regex: String; let label: String; let hard: Bool }

    private let markers: [Marker] = [
        Marker(regex: #"\bfatalError\s*\("#,          label: "fatalError",         hard: true),
        Marker(regex: #"\bpreconditionFailure\s*\("#, label: "preconditionFailure", hard: true),
        Marker(regex: #"\bunimplemented\b"#,          label: "unimplemented",       hard: true),
        Marker(regex: #"\bnotImplemented\b"#,         label: "notImplemented",      hard: true),
        Marker(regex: #"Button\([^)]*\)\s*\{\s*\}"#,  label: "empty Button action", hard: true),
        Marker(regex: #"//\s*(stub|placeholder|deferred)\b"#, label: "stub comment", hard: true),
        Marker(regex: #"\bTODO\b"#,  label: "TODO",  hard: false),
        Marker(regex: #"\bFIXME\b"#, label: "FIXME", hard: false),
        Marker(regex: #"\bXXX\b"#,   label: "XXX",   hard: false),
        Marker(regex: #"\bHACK\b"#,  label: "HACK",  hard: false),
    ]

    func scan(projectPath: String) async -> [StubMarkerFinding] {
        var results: [StubMarkerFinding] = []
        let root = URL(fileURLWithPath: projectPath)
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]) else { return results }

        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "swift" || url.pathExtension == "rs",
                  !url.path.contains("Tests/"),
                  !url.path.contains("/.build/"),
                  // The scanner's own marker table embeds the marker vocabulary.
                  url.lastPathComponent != "StubMarkerScanner.swift",
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }

            let lines = text.components(separatedBy: .newlines)
            for (idx, line) in lines.enumerated() {
                for marker in markers {
                    guard let range = line.range(
                        of: marker.regex, options: .regularExpression) else { continue }
                    // A marker inside a "..." string literal is data, not a code marker.
                    if isInsideStringLiteral(line: line, matchStart: range.lowerBound) {
                        continue
                    }
                    results.append(StubMarkerFinding(
                        file: url.path,
                        line: idx + 1,
                        marker: marker.label,
                        isHardStub: marker.hard,
                        context: line.trimmingCharacters(in: .whitespaces)))
                }
            }
        }
        return results
    }

    /// True when `matchStart` lies inside a `"..."` string literal on `line`.
    private func isInsideStringLiteral(line: String, matchStart: String.Index) -> Bool {
        var insideString = false
        var previous: Character?
        var index = line.startIndex
        while index < matchStart {
            let ch = line[index]
            if ch == "\"" && previous != "\\" { insideString.toggle() }
            previous = ch
            index = line.index(after: index)
        }
        return insideString
    }
}
```

## 2. Edit: Merlin/Discipline/Finding.swift
Add `case stubbedImplementation` to `FindingCategory` (after `ungatedTarget`).
**Then update `MerlinTests/Unit/FindingModelTests.swift`** — add
`XCTAssertEqual(FindingCategory.stubbedImplementation.rawValue, "stubbedImplementation")`
alongside the other per-case assertions, and adjust any `allCases.count` assertion.

## 3. Edit: Merlin/Discipline/DisciplineEngine.swift
Same wiring pattern phase 307b established for `TargetGateScanner`:

- **Stored property:** `private let stubMarkerScanner: StubMarkerScanner`
- **Init parameter** (defaulted, so existing call sites are unaffected) — insert after
  `targetGateScanner:`:
  ```swift
        targetGateScanner: TargetGateScanner = TargetGateScanner(),
        stubMarkerScanner: StubMarkerScanner = StubMarkerScanner(),
        storePath: String,
  ```
  and `self.stubMarkerScanner = stubMarkerScanner` in the body.
- **In `scan(projectPath:)`** add the parallel scan and extend the tuple await:
  ```swift
  async let stubMarkers = stubMarkerScanner.scan(projectPath: projectPath)
  ```
  ```swift
  let (drift, gaps, refs, why, ungated, stubs) = await (
      driftFindings, coverageGaps, docRefs, whyTriggers, ungatedTargets, stubMarkers)
  ```
- **Conversion block** — after the ungated-targets block:
  ```swift
  // Stub / deferred-work markers — unfinished code that compiles green.
  for stub in stubs {
      let name = URL(fileURLWithPath: stub.file).lastPathComponent
      let f = Finding(
          id: UUID(),
          category: .stubbedImplementation,
          severity: stub.isHardStub ? .nudge : .silent,
          summary: "\(name):\(stub.line)",
          detail: "\(stub.marker): \(stub.context)",
          suggestedAction: stub.isHardStub
              ? "Finish this implementation or remove the dead path."
              : "Resolve or remove the deferred-work marker.",
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
  -only-testing:MerlinTests/StubMarkerScannerTests -only-testing:MerlinTests/FindingModelTests 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|error:'
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|warning:|BUILD (SUCCEEDED|FAILED)'
```
Expected: `StubMarkerScannerTests` and `FindingModelTests` pass; BUILD SUCCEEDED, zero
warnings.

## Commit
```
git add Merlin/Discipline/StubMarkerScanner.swift Merlin/Discipline/Finding.swift \
  Merlin/Discipline/DisciplineEngine.swift MerlinTests/Unit/FindingModelTests.swift \
  phases/phase-308b-stub-marker-scanner.md
git commit -m "Phase 308b — StubMarkerScanner: surface unfinished code as discipline findings"
```
