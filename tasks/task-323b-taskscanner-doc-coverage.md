# Task 323b — TaskScanner Reads All Task Docs; Drift Is Always a Nudge

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 323a complete: failing runtime tests in `TaskScannerDocCoverageTests` and
`DisciplineEngineTaskDriftSeverityTests`.

W4 trace audit finding F4. Two edits, two files:
1. `TaskScanner.extractDeclaredSurfaces` reads every task doc — `a`, `b`, and the
   `diag-*` series — not only `task-\d+b-`. The "New surface introduced in task" block
   lives in the `a` doc per the project template.
2. `DisciplineEngine.scan` surfaces `.red`/`.yellow`/`.orange` drift, all as `.nudge`.
   Task drift is advisory — a symbol declared 200  tasks ago and since refactored is
   normal evolution, not a commit-blocker.

No new public surface — both edits modify existing methods.

---

## 1. Edit: Merlin/Discipline/TaskScanner.swift

In `extractDeclaredSurfaces(tasksDir:)`, replace the `nnbFiles` filter and the loop
header that consumes it. Change:
```swift
        let nnbFiles = files
            .filter { file in
                let name = file.lastPathComponent
                return name.hasPrefix("task-")
                    && name.hasSuffix(".md")
                    && name.range(of: #"task-\d+b-"#, options: .regularExpression) != nil
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var result: [DeclaredSurface] = []
        for file in nnbFiles {
```
to:
```swift
        // Read every task document — the `a` (tests) and `b` (implementation) tiers
        // and the `diag-*` series. The "New surface introduced in task" block lives in
        // the `a` doc per the project template, so the former `task-\d+b-` filter saw
        // almost no declared surface. Files with no such block contribute nothing.
        let taskDocFiles = files
            .filter { file in
                let name = file.lastPathComponent
                return name.hasSuffix(".md")
                    && (name.hasPrefix("task-") || name.hasPrefix("diag-"))
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var result: [DeclaredSurface] = []
        for file in taskDocFiles {
```

## 2. Edit: Merlin/Discipline/DisciplineEngine.swift

In `scan(projectPath:)`, replace the drift-to-finding loop header. Change:
```swift
            // Convert drift findings to queue findings.
            for d in drift where d.severity == .red || d.severity == .orange {
                let f = Finding(
                    id: UUID(),
                    category: .taskDrift,
                    severity: d.severity == .red ? .block : .nudge,
```
to:
```swift
            // Convert drift findings to queue findings. Surface red (absent),
            // yellow (signature-drift) and orange (undeclared) drift — all as nudges.
            // Task drift is advisory: a symbol declared many  tasks ago and since
            // refactored is normal evolution, not a commit-blocker. green = no-op.
            for d in drift where d.severity == .red
                || d.severity == .yellow || d.severity == .orange {
                let f = Finding(
                    id: UUID(),
                    category: .taskDrift,
                    severity: .nudge,
```
Leave the rest of the loop body (`summary`, `detail`, `suggestedAction`, `queue.add`,
`findings.append`) unchanged.

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E 'Test Case .*(passed|failed)|TEST (SUCCEEDED|FAILED)|error:|warning:|BUILD (SUCCEEDED|FAILED)' \
  | tail -60
xcodebuild -scheme MerlinTests-Live build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: the full `MerlinTests` suite passes — including 323a's two test classes — and
`MerlinTests-Live` compiles; BUILD SUCCEEDED, zero warnings.

The full suite is run deliberately (not a hand-picked subset): broadening the task-doc
filter changes `TaskScanner` output for any test with task-doc fixtures, and the
severity change touches every `taskDrift` finding. **If a failure appears in a test
unrelated to `TaskScanner` / `DisciplineEngine` / discipline findings, it is
pre-existing rot — STOP and report it; do not commit and do not try to fix it in this
task.**

## Commit
```
git add Merlin/Discipline/TaskScanner.swift Merlin/Discipline/DisciplineEngine.swift \
  tasks/task-323b- taskscanner-doc-coverage.md
git commit -m "Task 323b — TaskScanner reads all task docs; drift is always a nudge"
```
