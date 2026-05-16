# Phase 317b — ReachabilityScanner Injection-Detection Fix

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Phase 317a complete: failing runtime tests in `ReachabilityScannerInjectionTests`.

Fixes the two `unwiredComponent` false positives: `injectedTypes` now reads
`@StateObject` / `@ObservedObject` type annotations (not only inline constructors), and
the per-line heuristics skip comment lines (so a doc comment cannot register a consumer).

`ReachabilityScanner.swift` is in `Merlin/Discipline/` — pure Foundation, compiled into
both the app and the `merlin-discipline` CLI.

---

## 1. Edit: Merlin/Discipline/ReachabilityScanner.swift

**1a.** In `scan(projectPath:)`, the per-line heuristics loop currently reads:
```swift
        for source in sources {
            for line in source.lines {
                if let view = declaredViewName(in: line), (frequency[view] ?? 0) <= 1 {
```
Add a comment-line skip as the first statement inside `for line in source.lines {`:
```swift
            for line in source.lines {
                // Comments are discussion, not code — never mine them for a View
                // declaration or an environment-object consumer.
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                if let view = declaredViewName(in: line), (frequency[view] ?? 0) <= 1 {
```
(The global `frequency` map is built in the earlier loop and is left unchanged — counting
identifiers in comments there is the safe direction.)

**1b.** Replace the whole `injectedTypes(in:)` method with this version — it also reads
`@StateObject` / `@ObservedObject` property type annotations:
```swift
    /// Type names this line shows being created or owned for environment injection:
    /// inline constructors on a `.environmentObject(...)` / `@StateObject` /
    /// `@ObservedObject` line, plus the declared type of such a property.
    private func injectedTypes(in line: String) -> [String] {
        guard line.contains(".environmentObject(")
            || line.contains("@StateObject")
            || line.contains("@ObservedObject") else { return [] }
        var types: Set<String> = []

        // Inline-constructed types: `SomeType(...)`.
        if let ctor = try? NSRegularExpression(
            pattern: #"\b([A-Z][A-Za-z0-9_]*)\s*\("#) {
            let ns = line as NSString
            for m in ctor.matches(
                in: line, range: NSRange(location: 0, length: ns.length)) {
                if let r = Range(m.range(at: 1), in: line) {
                    types.insert(String(line[r]))
                }
            }
        }
        // Declared property type: `@StateObject ... var x: SomeType`.
        if let annot = try? NSRegularExpression(pattern:
            #"@(?:StateObject|ObservedObject)\s+(?:(?:private|public|internal|fileprivate)\s+)?var\s+\w+\s*:\s*([A-Z][A-Za-z0-9_]*)"#) {
            let ns = line as NSString
            if let m = annot.firstMatch(
                in: line, range: NSRange(location: 0, length: ns.length)),
               let r = Range(m.range(at: 1), in: line) {
                types.insert(String(line[r]))
            }
        }
        return Array(types)
    }
```

`declaredViewName`, `environmentObjectType`, `swiftFiles`, and the rest of `scan` are
unchanged.

## 2. Edit: phases/phase-309b-reachability-scanner.md
Add a one-line banner under that doc's title:
```
> **Note:** `injectedTypes` and the per-line loop here are refined by phase 317b
> (annotation-based injection detection, comment-line skip). Implement 317b's version.
```

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/ReachabilityScannerInjectionTests -only-testing:MerlinTests/ReachabilityScannerTests 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|error:'
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|warning:|BUILD (SUCCEEDED|FAILED)'
```
Expected: `ReachabilityScannerInjectionTests` and the original `ReachabilityScannerTests`
all pass; BUILD SUCCEEDED, zero warnings.

## Commit
```
git add Merlin/Discipline/ReachabilityScanner.swift phases/phase-309b-reachability-scanner.md \
  phases/phase-317b-reachability-injection.md
git commit -m "Phase 317b — ReachabilityScanner reads annotation injection, skips comments"
```
