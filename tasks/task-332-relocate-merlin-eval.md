# Phase 332 — Relocate merlin-eval into the merlin repo

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 331b complete: `DisciplineExclusions` blacklist wired into every file-walking
discipline scanner; `merlin-eval` is on the blacklist.

The eval suite (`merlin-eval/` — specs, fixture docs, built fixtures) currently sits at
`~/Documents/localProject/merlin-eval/`, a sibling of the merlin repo, and is **not
version-controlled at all**. This phase moves it inside the merlin repo, fixes the
harness path resolution, and commits it. The discipline scanners already skip it
(phase 331b), so no false findings result.

This is an operational/relocation phase — no new testable surface. Verification is the
`MerlinTests-Live` compile gate (`EvalSupport.swift` lives in `MerlinE2ETests`) plus a
check that the move happened.

> Pre-flight: `~/Documents/localProject/merlin-eval/` must exist and `~/Documents/
> localProject/merlin/merlin-eval/` must NOT exist. If either is false, stop and report.

---

## Step 1 — Move the directory
```
mv ~/Documents/localProject/merlin-eval ~/Documents/localProject/merlin/merlin-eval
```
Do **not** add `merlin-eval/` to `project.yml` — it is data/fixtures, never compiled
into a target. No `xcodegen generate` is needed (no project structure changes; only
string literals in an existing file change in Step 2).

## Step 2 — Edit `MerlinE2ETests/EvalSupport.swift`

`EvalPaths.root` stays `.../localProject` (it is still computed three parents up from
this file, and `EvalPaths.sibling(_:)` still needs it to resolve `xcalibre-server`).
Only the `merlin-eval/...` path prefixes change to `merlin/merlin-eval/...`.

### Edit A — the `EvalPaths` doc comment
old:
```swift
/// Resolves `merlin-eval/<...>` - a sibling of the `merlin` repo - from this source
/// file's location, so the harness needs no env var or absolute path.
```
new:
```swift
/// Resolves `merlin-eval/<...>` - the eval suite, which lives inside the `merlin` repo
/// at `merlin/merlin-eval/` - from this source file's location, so the harness needs no
/// env var or absolute path.
```

### Edit B — `EvalPaths.fixture(_:)`
old:
```swift
        root.appendingPathComponent("merlin-eval/fixtures/\(name)").path
```
new:
```swift
        root.appendingPathComponent("merlin/merlin-eval/fixtures/\(name)").path
```

### Edit C — the `EvalLog` doc comment
old:
```swift
/// Appends a scenario's captured run to `merlin-eval/results/` - every value logged end
```
new:
```swift
/// Appends a scenario's captured run to `merlin/merlin-eval/results/` - every value logged end
```

### Edit D — `EvalLog.write(scenario:summary:)`
old:
```swift
        let dir = EvalPaths.root.appendingPathComponent("merlin-eval/results")
```
new:
```swift
        let dir = EvalPaths.root.appendingPathComponent("merlin/merlin-eval/results")
```

## Step 3 — Sync the task-326 doc
`tasks/task-326-eval-capability-harness.md` contains the full `EvalSupport.swift`
listing. Apply the **same** Edits A–D to that listing inside the task doc, and append a
`## Fixes` section:
```
## Fixes
Phase 332 relocated `merlin-eval/` into the merlin repo (`merlin/merlin-eval/`).
`EvalPaths.fixture(_:)` and `EvalLog`'s results directory now resolve
`merlin/merlin-eval/...`; `EvalPaths.root` and `EvalPaths.sibling(_:)` are unchanged.
```

## Step 4 — `.gitignore` — append the eval build-artifact ignores
Append to the repo-root `.gitignore`:
```
# Eval suite (merlin-eval/) — fixture *sources* and the OCR image are tracked; the
# regenerable build outputs are not.
merlin-eval/fixtures/**/target/
merlin-eval/fixtures/**/ledger.txt
merlin-eval/fixtures/electronics/*
!merlin-eval/fixtures/electronics/schematic-image/
```
The `electronics/*` + `!.../schematic-image/` pair tracks the OCR fixture
(`schematic-image/`) while ignoring everything else written into `electronics/` (the
harness's `.mcp.json`, and the `.kicad_sch`/`.kicad_pcb`/ngspice files Merlin generates
during an S6 run).

## Step 5 — Keep the results directory
The proving suite writes `merlin-eval/results/SN-<date>.md`. Git cannot track an empty
directory, so create a placeholder:
```
touch ~/Documents/localProject/merlin/merlin-eval/results/.gitkeep
```

---

## Verify
```
cd ~/Documents/localProject/merlin
ls -d merlin-eval/fixtures && echo "move OK"
test ! -e ~/Documents/localProject/merlin-eval && echo "old path gone OK"
xcodebuild -scheme MerlinTests-Live build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
git status --short | grep -E 'target/|ledger.txt' && echo "LEAK — build artifact staged" || echo "no build artifacts staged OK"
```
Expected: `merlin-eval/fixtures` exists under the repo; the old sibling path is gone;
`MerlinTests-Live` **BUILD SUCCEEDED** with zero warnings; no `target/` or `ledger.txt`
path appears in `git status` (the `.gitignore` excludes them).

## Commit
```
git add merlin-eval .gitignore MerlinE2ETests/EvalSupport.swift \
        tasks/task-326-eval-capability-harness.md \
        tasks/task-332-relocate-merlin-eval.md
git commit -m "Phase 332 — Relocate merlin-eval into the merlin repo"
git status --short
```
`git status` after the commit should be clean (aside from any intentionally-untracked
build outputs).

## Notes
- The pre-commit hook runs only the target-liveness gate (`project.yml`); `merlin-eval`
  is not a target, so the commit is not blocked.
- For the `merlin-eval` blacklist to take effect in the *installed* discipline CLI
  (`~/.merlin/bin/merlin-discipline`) and the app's runtime scan, rebuild and reinstall
  that binary (via the app's discipline installer or the `merlin-discipline` scheme).
  Not blocking — the pre-commit gate never walks fixture files.
- Follow-up (non-blocking): `tasks/PASTE-LIST.md` and any loose W4/W5 prompt artifacts
  still say `merlin-eval/...`; those paths now mean `merlin/merlin-eval/...`.
