# Phase 318b — StubMarkerScanner Tuning

> **Note:** phase 319b adds build/ + DerivedData/ skips to scan's file guard.

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Phase 318a complete: failing runtime tests in `StubMarkerScannerTuningTests`.

Removes the two `stubbedImplementation` false positives: empty `.cancel`-role buttons
(idiomatic SwiftUI) and markers inside `"""` multi-line string literals (template
content). `StubMarkerScanner.swift` is in `Merlin/Discipline/` — pure Foundation,
compiled into both the app and the `merlin-discipline` CLI.

---

## 1. Edit: Merlin/Discipline/StubMarkerScanner.swift
Replace the whole `scan(projectPath:)` method with this version — it tracks `"""`
multi-line string fences and skips empty `.cancel`-role buttons:

```swift
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
            var inMultilineString = false
            for (idx, line) in lines.enumerated() {
                let tripleQuotes = line.components(separatedBy: "\"\"\"").count - 1
                // Lines inside a `"""` multi-line string literal are content, not code.
                if inMultilineString {
                    if tripleQuotes % 2 == 1 { inMultilineString = false }
                    continue
                }
                for marker in markers {
                    guard let range = line.range(
                        of: marker.regex, options: .regularExpression) else { continue }
                    // A marker inside a single-line "..." literal is data, not a marker.
                    if isInsideStringLiteral(line: line, matchStart: range.lowerBound) {
                        continue
                    }
                    // An empty-bodied `.cancel`-role button is idiomatic SwiftUI — the
                    // dialog dismisses itself; the empty action is correct, not a stub.
                    if marker.label == "empty Button action", line.contains(".cancel") {
                        continue
                    }
                    results.append(StubMarkerFinding(
                        file: url.path,
                        line: idx + 1,
                        marker: marker.label,
                        isHardStub: marker.hard,
                        context: line.trimmingCharacters(in: .whitespaces)))
                }
                if tripleQuotes % 2 == 1 { inMultilineString = true }
            }
        }
        return results
    }
```

The `markers` table and `isInsideStringLiteral(line:matchStart:)` are unchanged.

## 2. Edit: phases/phase-308b-stub-marker-scanner.md
Add a one-line banner under that doc's title:
```
> **Note:** the `scan` method here is refined by phase 318b (skip empty `.cancel`
> buttons, track `"""` multi-line strings). Implement 318b's version.
```

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/StubMarkerScannerTuningTests -only-testing:MerlinTests/StubMarkerScannerTests 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|error:'
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|warning:|BUILD (SUCCEEDED|FAILED)'
```
Expected: `StubMarkerScannerTuningTests` and the original `StubMarkerScannerTests` all
pass; BUILD SUCCEEDED, zero warnings.

## Commit
```
git add Merlin/Discipline/StubMarkerScanner.swift phases/phase-308b-stub-marker-scanner.md \
  phases/phase-318b-stub-marker-tuning.md
git commit -m "Phase 318b — StubMarkerScanner skips .cancel buttons and multi-line strings"
```
