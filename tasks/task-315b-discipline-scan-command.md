# Task 315b — `merlin-discipline scan` Command

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Task 315a complete: failing tests in `DisciplineScanReportTests`.

Adds a `scan` subcommand to the `merlin-discipline` CLI. It builds a `DisciplineEngine`,
runs the full scan, and prints every finding grouped by category. It is informational —
always exits 0, never blocks. `DisciplineCLI.swift` is in `Merlin/Discipline/` — pure
Foundation, compiled into the app and the CLI.

---

## Edit: Merlin/Discipline/DisciplineCLI.swift

**1. Add the `scan` case to the subcommand `switch` in `run(arguments:)`:**
```swift
case "scan":
    return await runScan(projectPath: projectPath)
```

**2. Add the report formatter — `internal` (not `private`) so it is unit-testable:**
```swift
/// Renders discipline findings as a human-readable report, grouped by category.
static func formatScanReport(_ findings: [Finding]) -> String {
    guard !findings.isEmpty else {
        return "merlin-discipline scan: no findings."
    }
    var out = "merlin-discipline scan: \(findings.count) finding(s)\n"
    let byCategory = Dictionary(grouping: findings, by: { $0.category.rawValue })
    for category in byCategory.keys.sorted() {
        out += "\n[\(category)]\n"
        for f in (byCategory[category] ?? []).sorted(by: { $0.summary < $1.summary }) {
            out += "  (\(f.severity.rawValue)) \(f.summary) — \(f.detail)\n"
        }
    }
    return out
}
```

**3. Add the `runScan` handler** (next to `runPostCommit` / `runPrePush` /
`runPreCommit`). It constructs a `DisciplineEngine` with the six explicit scanners; the
liveness scanners added in  tasks 307–309 come in through their defaulted init
parameters, so the full scan runs:
```swift
private static func runScan(projectPath: String) async -> Int32 {
    print("merlin-discipline: scan \(projectPath)")
    let adapter = await DisciplineEngine.resolveProjectAdapter(projectPath: projectPath)
    let storePath = URL(fileURLWithPath: projectPath, isDirectory: true)
        .appendingPathComponent(".merlin/pending.json").path
    let engine = DisciplineEngine(
        adapter: adapter,
        taskScanner: TaskScanner(),
        manualCoverageScanner: ManualCoverageScanner(),
        docReferenceGraph: DocReferenceGraph(),
        whyCommentScanner: WhyCommentScanner(),
        proseReadabilityChecker: ProseReadabilityChecker(),
        storePath: storePath)
    let report = await engine.scan(projectPath: projectPath)
    print(formatScanReport(report.findings))
    return 0
}
```

**4. Update `printUsage()`** so the usage line reads:
```
usage: merlin-discipline <scan|pre-commit|post-commit|pre-push> <project-path>
```
If `DisciplineCLITests` asserts the exact usage string, update that assertion to match.

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/DisciplineScanReportTests -only-testing:MerlinTests/DisciplineCLITests 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|error:'
xcodebuild -scheme merlin-discipline build -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|warning:|BUILD (SUCCEEDED|FAILED)'
```
Expected: `DisciplineScanReportTests` and `DisciplineCLITests` pass; the
`merlin-discipline` CLI target builds with zero warnings.

## Commit
```
git add Merlin/Discipline/DisciplineCLI.swift tasks/task-315b-discipline-scan-command.md
git commit -m "Task 315b — merlin-discipline scan: print all discipline findings"
```
