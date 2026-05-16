# Phase 312 — Verification Gate Update (CLAUDE.md + gating config)

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Phase 311b complete: `LivenessGate` + pre-commit hook landed.

Liveness Discipline batch, final unit (6 of 6). The root cause of the ~160-phase
`MerlinLiveTests` / `MerlinE2ETests` rot: the per-phase verification gate only ever
compiled the `MerlinTests` scheme — which builds neither of those targets nor
`TestTargetApp`. `TargetGateScanner` now *detects* that condition; this phase *closes*
it by folding the live scheme into the standard gate.

This is a documentation + config phase — no Swift source changes. It still ends with a
commit, per the phase protocol.

---

## 1. Edit: CLAUDE.md — Build Verification Commands

Replace the entire fenced `bash` block in the **"## Build Verification Commands"**
section with the block below. Changes: every command carries the code-signing-bypass
flags (the machine has no `Merlin Dev Signing` cert), and a third command compiles the
live/E2E scheme.

```bash
# Build for testing (unit gate)
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40

# Run unit tests
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40

# Live/E2E compile gate — compiles MerlinLiveTests, MerlinE2ETests, TestTargetApp.
# build-for-testing only COMPILES (no run), so it needs no API keys and no LM Studio.
# Omitting this is how those three targets rotted uncompiled for ~160 phases.
xcodebuild -scheme MerlinTests-Live build-for-testing \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40

# Regenerate project after editing project.yml
xcodegen generate
```

Immediately below that fenced block, add this paragraph:

> **Both schemes are part of the gate.** Every phase's Verify must keep `MerlinTests`
> *and* `MerlinTests-Live` compiling. `MerlinTests` builds the app + unit tests;
> `MerlinTests-Live` builds the live/E2E targets the unit scheme never touches. A target
> compiled by neither scheme rots silently — `TargetGateScanner` (Project Discipline)
> flags that condition, but compiling the scheme every phase is the real prevention.

## 2. Edit: CLAUDE.md — Phase Sheet Format

In the **"## Phase Sheet Format"** section, in the `### phases/phase-NNb-...` template,
change the `## Verify` placeholder line so it reads:

```
## Verify
<xcodebuild — both MerlinTests and, when test targets in the live scheme changed,
 MerlinTests-Live. Expected: BUILD SUCCEEDED, all NNa tests pass>
```

## 3. Edit: .merlin/project.toml

Phase 307b created this file with `gating_schemes = ["MerlinTests"]`. Now that the live
scheme is part of the gate, add it:
```toml
gating_schemes = ["MerlinTests", "MerlinTests-Live"]
```
This stops `TargetGateScanner` from flagging `MerlinLiveTests`, `MerlinE2ETests`, and
`TestTargetApp` — they are now exercised by a gating scheme.

---

## Verify
Confirm the documentation and config changes, then confirm the live scheme genuinely
compiles (it must, since phases 302c + 303b revived and completed it):
```
grep -c 'MerlinTests-Live' CLAUDE.md            # expect >= 1
grep 'gating_schemes' .merlin/project.toml      # expect both schemes listed
xcodegen generate
xcodebuild -scheme MerlinTests-Live build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|warning:|BUILD (SUCCEEDED|FAILED)'
```
Expected: `MerlinTests-Live` appears in CLAUDE.md; `.merlin/project.toml` lists both
gating schemes; BUILD SUCCEEDED with zero warnings.

## Commit
```
git add CLAUDE.md .merlin/project.toml phases/phase-312-verification-gate-update.md
git commit -m "Phase 312 — Fold MerlinTests-Live into the verification gate"
```
