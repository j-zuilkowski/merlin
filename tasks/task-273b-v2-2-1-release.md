# Task 273b — v2.2.1 Release

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 273a complete: failing tests asserting v2.2.1 version and `RELEASE-v2.2.1.md`.

This task ships **v2.2.1 — Project Discipline remediation**. It bumps the project
version, writes release notes, corrects the developer manual, regenerates the Xcode
project, and tags. v2.2.1 wires the v2.2 discipline subsystem into the running app and
fixes the correctness bugs found in code review ( tasks 266–272).

---

## Edit: project.yml

Locate the version fields and update:

```yaml
# Before:
MARKETING_VERSION: "2.2.0"
CURRENT_PROJECT_VERSION: 17

# After:
MARKETING_VERSION: "2.2.1"
CURRENT_PROJECT_VERSION: 18
```

---

## Edit: constitution.md

Update the "Current version" line near the bottom of the file:

```markdown
# Before:
**Current version: 2.1.0** (build 16, tag `v2.1.0`)

# After:
**Current version: 2.2.1** (build 18, tag `v2.2.1`)
```

(If a prior release already advanced this line to `2.2.0`, replace that value instead —
the end state is `2.2.1 (build 18, tag v2.2.1)`.)

---

## Edit: Merlin/Docs/DeveloperManual.md

In the `## DisciplineEngine (v2.2)` section, the prose currently says the engine
"coordinates five scanners". After task 270b the engine genuinely runs all five — the
task-scanner, manual-coverage scanner, doc-reference graph, why-comment scanner, and
prose-readability checker. Verify the wording is accurate and, if it lists only four or
describes the prose checker as unused, correct it to state that all five scanners run on
every `scan()`. The intended sentence:

> `DisciplineEngine` is a top-level `actor`... It coordinates five scanners — the
> task scanner, manual-coverage scanner, doc-reference graph, why-comment scanner, and
> prose-readability checker — owns the pending-attention queue, and integrates with the
> hook engine.

No code change here; this is a documentation correction so the manual matches the
post-270b behaviour.

---

## Write to: RELEASE-v2.2.1.md (new file at repository root)

```markdown
# Merlin v2.2.1 — Project Discipline Remediation

Released: 2026-05-15

## Summary

v2.2.1 — Project Discipline remediation. Wires the v2.2 discipline subsystem into the
running app and fixes correctness bugs found in code review.

## What's new

- **The discipline subsystem is now live in the app (task 272).** `AppState` builds a
  `DisciplineEngine` and a `PendingAttentionViewModel` at init, installs the seed
  adapters into `~/.merlin/adapters`, runs the `SessionStart` hook to surface the top
  findings at session open, and runs a discipline scan after every turn. `ChatView`
  shows the pending-attention chip in the chat header. In v2.2.0 the subsystem shipped
  but never executed.

## Internal changes

- **Finding idempotency (task 266).** `Finding` gains a content-derived `dedupKey`
  (category + summary). `PendingAttentionQueue` is re-keyed by it, so a re-scan of an
  unchanged project collapses onto existing queue entries instead of growing
  `pending.json` without bound.
- **Doc-reference accuracy (task 267).** `DisciplineEngine` no longer emits a stale
  finding for every healthy doc reference. `DocReferenceGraph.danglingReferences`
  reports only doc mentions of code symbols that do not exist in the source tree.
- **Scanner accuracy (task 268).** `TaskScanner` now excludes test targets
  (`MerlinTests` and friends), so public test symbols no longer produce spurious
  "undocumented" findings. `WhyCommentScanner` skips trigger patterns that appear only
  inside comments or string literals, removing false-positive pre-commit blocks.
  `DocReferenceGraph` associates each reference with the heading it appears under.
- **Adapter-key consistency (task 269).** `AdapterRegistry.loadFromDirectory` registers
  adapters under their adapter-key (`swift-xcode`, `rust-cargo`) so
  `adapter(for: config.adapter)` resolves for real projects.
- **Prose readability (task 270).** The Vale style file uses Vale's real `readability`
  rule, the checker parses Vale's actual JSON output, and `DisciplineEngine` now runs
  the prose checker over project docs.
- **Process and git-hook safety (task 271).** `GitHookInstaller` refuses to clobber a
  pre-existing non-Merlin hook. `APIDocGenerator` and `ProseReadabilityChecker` gain
  process timeouts so a hung child cannot stall the app. `OverrideAuditLog` no longer
  force-unwraps.
- **Release-version tests updated.** The legacy `AppVersionTests` now assert the v2.2.1
  marketing version and build number, so the old 2.2.0 / build 17 expectations do not
  regress during the release bump.

## Migration

No migration required. v2.2.1 is a remediation release over v2.2.0 — all changes are
internal correctness fixes plus the app wiring that activates the existing v2.2
subsystem. Projects without a `.merlin/` directory are unaffected, exactly as in v2.2.0.

**Build number**: 18 (was 17 in v2.2.0).
```

---

## Steps

After writing the files above, run in order:

```bash
# 1. Regenerate the Xcode project
cd ~/Documents/localProject/merlin
xcodegen generate

# 2. Build and confirm
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40

# 3. Run all tests
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED** and all task 273a tests pass (version 2.2.1, build 18,
release notes present). No prior task regresses.

## Commit

```bash
git add tasks/task-273b-v2-2-1-release.md \
    project.yml \
    constitution.md \
    RELEASE-v2.2.1.md \
    Merlin/Docs/DeveloperManual.md
git commit -m "Task 273b — Bump version to 2.2.1 (build 18)"
```

## Tag

```bash
git tag v2.2.1
```

Do NOT push and do NOT create the GitHub release as part of this task. Pushing the tag
and running `gh release create v2.2.1 --notes-file RELEASE-v2.2.1.md --latest` is a
separate, explicit follow-up step the user performs manually — matching how the v2.2.0
release (task 265b) was handled. The task ends at the local commit + local tag.
