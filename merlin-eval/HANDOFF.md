# Merlin Proving-Readiness — Session Handoff

You are picking up a multi-session effort to make **Merlin** (a macOS SwiftUI agentic
coding app) provably correct, then build an exhaustive eval/proving suite for it. This
brief is self-contained — read it, then continue at **W4** below.

Recommended model: keep a strong model for W4 (the trace audit is deep cross-file
reasoning where missing things is the failure mode). Sonnet is acceptable for W5.

---

## Your role — read this first

**You author phase documents; the Codex app executes them.** Do NOT directly
implement, build, or commit Merlin *source* for multi-phase work. You write
`phases/phase-NNa-*.md` (failing tests) and `phase-NNb-*.md` (implementation) as TDD
pairs; the user runs them through Codex. You MAY directly: do research/audits, read
code, run read-only commands, edit phase docs and spec docs.

- Project: `~/Documents/localProject/merlin` — Swift 5.10, macOS 14+, SwiftUI, xcodegen
  (`project.yml` is source of truth), `SWIFT_STRICT_CONCURRENCY=complete`, non-sandboxed.
- The repo's `CLAUDE.md` holds the binding rules. Read it.
- Git: commit locally only; **never push** without an explicit "push"; **never commit**
  without an explicit request.
- Next free phase number: **320**.

### Phase-doc defect classes that stop Codex — check every doc you write
1. **Deletion/addition gaps** — deleting a symbol a test/doc still references; adding a
   `FindingCategory` case without updating `MerlinTests/Unit/FindingModelTests.swift`.
2. **`build-for-testing` vs `test` verb** — a *compile-failure* phase verifies with
   `build-for-testing` (BUILD FAILED); a *runtime-failure* phase verifies with `test`
   (BUILD SUCCEEDED, the test fails). Getting this wrong stops Codex.
3. **Code that won't compile against real APIs** — verify signatures against source.
4. **Non-existent scheme/target/path** — valid schemes: `Merlin`, `MerlinTests`,
   `MerlinTests-Live`, `merlin-discipline`. Verify commands need
   `CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`.

---

## The plan — W1 through W5

| | Work | Status |
|---|---|---|
| W1 | Arm the discipline pre-commit gate (auto-install at app launch) | **done** — phases 313 |
| W2 | Make discipline scanners runnable + trustworthy | **done** — phases 314–319 |
| W3 | Accessibility-ID coverage gaps | tracked in `merlin-eval/scenarios/S7–S11` — folded into W5 |
| **W4** | **Trace-the-calls audit of the live codebase** | **NEXT — start here** |
| W5 | Build the S1–S17 eval fixtures + run the proving suite | after W4 |

W4 must finish before W5 (user instruction).

---

## Current state (committed)

- All phases **294–319** + **302c** committed. HEAD ≈ `819f3a1` (Phase 319b).
  (294–306 = a "wiring" batch that wired up Merlin's dormant v2.2 Discipline subsystem;
  307–312 = "Liveness Discipline" — 4 new scanners + a pre-commit gate; 313 = gate
  auto-install; 314–319 = discipline `scan` CLI + scanner tuning.)
- The discipline gate is **live**: it auto-installs `~/.merlin/bin/merlin-discipline` +
  git hooks at app launch for projects whose `.merlin/project.toml` opts into the
  `pre_commit` layer (the Merlin repo does). The `pre-commit` hook blocks commits on
  ungated targets.
- `merlin-discipline scan <path>` runs the full discipline scan and prints findings.
  Rebuild + run: `xcodebuild -scheme merlin-discipline build -derivedDataPath /tmp/merlin-derived`
  then `/tmp/merlin-derived/Build/Products/Debug/merlin-discipline scan ~/Documents/localProject/merlin`.
- Latest scan = **220 findings**: 214 `phaseDrift`, 4 `docStaleReference`, 2
  `stubbedImplementation`. (Down from an untuned 1798.)

### Uncommitted (known, leave unless asked)
- `Merlin.xcodeproj/project.pbxproj`, `.../MerlinTests-Live.xcscheme` — xcodegen-generated;
  `.xcodeproj/` is gitignored but these were tracked before the ignore rule. A one-time
  `git rm -r --cached Merlin.xcodeproj` would stop the drift permanently — only if asked.
- `phases/PASTE-LIST.md` — has uncommitted entries for phases 313–319. Commit it (with
  the user's OK) or let it ride with W4's first commit.

---

## W4 — the trace-the-calls audit (start here)

A deep audit of the live codebase. **Research only** — produce a written report; real
findings become phase docs (320+) for Codex. Do it directly.

### Scope — follow the code, do not trust green builds
- Every public type → a real call site (is it actually used, or dead?).
- Every `@EnvironmentObject` consumer → a matching `.environmentObject(...)` injection
  on a reachable ancestor (this is the crash class that started the whole effort).
- Every enum case → a producer (does anything emit it?).
- Every scanner / gate / generator / engine entry point → a real trigger.
- Specifically verify `DisciplineEngine.scan()` actually fires — it is called at
  `Merlin/App/AppState.swift:286`; confirm the enclosing code path runs at runtime.
- Sweep for dead controls (empty `{ }` SwiftUI actions), stubbed/deferred code.

### Seeded backlog (already confirmed — fix in W4)
1. **`Merlin/UI/Sidebar/WorkerDiffView.swift:39` and `:42`** — the "Reject All" and
   "Accept & Merge" toolbar buttons have empty `{ }` actions. Dead controls — they
   carry accessibility IDs (look wired) but do nothing. Wire them to the worker-diff
   staging buffer's reject-all / accept-and-merge.
2. **`architecture.md`** — contains `versionBumpCandidate`, a stale reference: phase 301
   deleted `FindingCategory.versionBumpCandidate` but missed `architecture.md`. Also
   `domain` / `shape` / `signature` are flagged there — classify illustrative vs. stale.
3. **`phaseDrift` — 214 findings** ("public symbol not declared in any phase NNb file").
   Triage: genuine drift vs. `PhaseScanner` signature-normalization noise. Run
   `merlin-discipline scan` to get the live list.

### Deliverable
A written audit report (suggest `merlin-eval/TRACE-AUDIT.md`), every finding classified
live / dead / partially-wired. Then author phase docs (320+) for the real findings;
the user runs them through Codex. Re-run `merlin-discipline scan` afterward to confirm.

---

## W5 — eval fixtures + proving run (after W4)

`merlin-eval/` (this directory, a sibling of `merlin`, not a git repo) holds the proving
suite: `README.md`, `BLOCKED.md`, `SURFACE-INVENTORY.md`, `scenarios/S1-*.md … S17-*.md`.
S1–S6 are capability scenarios; S7–S17 are surface-coverage scenarios. S7–S11 each
carry an "Accessibility-ID coverage" preflight note (that is W3 — fill AX-ID gaps as
each scenario is authored). W5 = build the fixtures/manifests/rubrics, author the
`MerlinE2ETests` harness phase docs (the `EvalHarness` already exists, phase 303), run
the suite, log results to `merlin-eval/results/`.

---

## Verification commands (from CLAUDE.md, post-phase-312)

```bash
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED'
# also gate the live scheme:
xcodebuild -scheme MerlinTests-Live build-for-testing  ... (same flags)
xcodegen generate   # after any project.yml change
```

---

## Running proving-suite scenarios locally (S1, S2, …)

The compile gates above force ad-hoc signing (`CODE_SIGNING_ALLOWED=NO`) so they
stay CI-portable. For **executing** a live scenario locally you MUST drop those
three flags, so the project's `Merlin Dev Signing` identity (from `project.yml`)
is actually used. Without it the test host re-signs ad-hoc on every rebuild, and
macOS TCC silently invalidates the `Merlin.app` Full Disk Access grant — every
`~/Documents`-touching subprocess then hangs forever (see runbook note below).

```bash
# Local proving-suite invocation — signed
xcodebuild -scheme MerlinTests-Live test \
  -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
  -only-testing:MerlinE2ETests/CapabilityScenarioTests/testS1SwiftGUIDebugCycle 2>&1 \
  | grep -E 'Test Case|TEST (EXECUTE )?(SUCCEEDED|FAILED)|passed \(|failed \(|skipped \('
```

**First-time setup (per machine, once):**

1. Build the live scheme once to materialise the signed app:
   `xcodebuild -scheme MerlinTests-Live build-for-testing -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived` (no signing-disable flags).
2. `System Settings → Privacy & Security → Full Disk Access → +` and add
   `/private/tmp/merlin-derived/Build/Products/Debug/Merlin.app`. Toggle on.

TCC keys the grant on the designated requirement (`identifier "com.merlin.app"
AND certificate leaf = "Merlin Dev Signing"`) — both stable across rebuilds. The
grant persists as long as the cert isn't regenerated. **Never** re-add this flag
set to a `git push` / CI pipeline; the dev cert is local-only and CI builds will
fail signing.

**Symptom of an unsigned (ad-hoc) test host:** `pristineFixtureCopy` times out
after 600s with `EvalShell timeout`, no LM Studio activity, telemetry shows the
test method never entered the agentic loop. The fix is always: rebuild with
signing, re-toggle the FDA entry. See `phases/phase-239b` Fixes for the full
post-mortem.
