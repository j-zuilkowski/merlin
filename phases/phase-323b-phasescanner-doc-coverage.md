# Phase 323b — PhaseScanner Reads All Phase Docs; Drift Is Always a Nudge

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 323a complete: failing runtime tests in `PhaseScannerDocCoverageTests` and
`DisciplineEnginePhaseDriftSeverityTests`.

W4 trace audit finding F4. Two edits, two files:
1. `PhaseScanner.extractDeclaredSurfaces` reads every phase doc — `a`, `b`, and the
   `diag-*` series — not only `phase-\d+b-`. The "New surface introduced in phase" block
   lives in the `a` doc per the project template.
2. `DisciplineEngine.scan` surfaces `.red`/`.yellow`/`.orange` drift, all as `.nudge`.
   Phase drift is advisory — a symbol declared 200 phases ago and since refactored is
   normal evolution, not a commit-blocker.

No new public surface — both edits modify existing methods.

---

## 1. Edit: Merlin/Discipline/PhaseScanner.swift

In `extractDeclaredSurfaces(phasesDir:)`, replace the `nnbFiles` filter and the loop
header that consumes it. Change:
```swift
        let nnbFiles = files
            .filter { file in
                let name = file.lastPathComponent
                return name.hasPrefix("phase-")
                    && name.hasSuffix(".md")
                    && name.range(of: #"phase-\d+b-"#, options: .regularExpression) != nil
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var result: [DeclaredSurface] = []
        for file in nnbFiles {
```
to:
```swift
        // Read every phase document — the `a` (tests) and `b` (implementation) tiers
        // and the `diag-*` series. The "New surface introduced in phase" block lives in
        // the `a` doc per the project template, so the former `phase-\d+b-` filter saw
        // almost no declared surface. Files with no such block contribute nothing.
        let phaseDocFiles = files
            .filter { file in
                let name = file.lastPathComponent
                return name.hasSuffix(".md")
                    && (name.hasPrefix("phase-") || name.hasPrefix("diag-"))
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var result: [DeclaredSurface] = []
        for file in phaseDocFiles {
```

## 2. Edit: Merlin/Discipline/DisciplineEngine.swift

In `scan(projectPath:)`, replace the drift-to-finding loop header. Change:
```swift
            // Convert drift findings to queue findings.
            for d in drift where d.severity == .red || d.severity == .orange {
                let f = Finding(
                    id: UUID(),
                    category: .phaseDrift,
                    severity: d.severity == .red ? .block : .nudge,
```
to:
```swift
            // Convert drift findings to queue findings. Surface red (absent),
            // yellow (signature-drift) and orange (undeclared) drift — all as nudges.
            // Phase drift is advisory: a symbol declared many phases ago and since
            // refactored is normal evolution, not a commit-blocker. green = no-op.
            for d in drift where d.severity == .red
                || d.severity == .yellow || d.severity == .orange {
                let f = Finding(
                    id: UUID(),
                    category: .phaseDrift,
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

The full suite is run deliberately (not a hand-picked subset): broadening the phase-doc
filter changes `PhaseScanner` output for any test with phase-doc fixtures, and the
severity change touches every `phaseDrift` finding. **If a failure appears in a test
unrelated to `PhaseScanner` / `DisciplineEngine` / discipline findings, it is
pre-existing rot — STOP and report it; do not commit and do not try to fix it in this
phase.**

## Commit
```
git add Merlin/Discipline/PhaseScanner.swift Merlin/Discipline/DisciplineEngine.swift \
  phases/phase-323b-phasescanner-doc-coverage.md
git commit -m "Phase 323b — PhaseScanner reads all phase docs; drift is always a nudge"
```
