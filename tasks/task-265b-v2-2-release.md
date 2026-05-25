# Phase 265b — v2.2.0 Release

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 265a complete: failing tests asserting v2.2.0 version and RELEASE-v2.2.0.md.

This phase bumps the project version to 2.2.0, writes release notes, regenerates the
Xcode project, tags, and publishes.

---

## Edit

### project.yml

Locate the version fields and update:

```yaml
# Before:
MARKETING_VERSION: 2.1.0
CURRENT_PROJECT_VERSION: 16

# After:
MARKETING_VERSION: 2.2.0
CURRENT_PROJECT_VERSION: 17
```

---

## Write to

### RELEASE-v2.2.0.md (new file at project root)

```markdown
# Merlin v2.2.0 — Project Discipline Subsystem

Released: 2026-05-14

## What's New

**Project Discipline Subsystem (v2.2.0)** — 25 task pairs (241a–265b) building the
construction-discipline layer directly into Merlin.

### Adapter System (241–242)

- `AdapterRegistry` + `ProjectAdapter` — per-language/per-toolchain configuration consumed
  by every discipline component. Seed adapters for Swift/Xcode and Rust/Cargo.
- `.merlin/project.toml` + `ProjectConfigLoader` — per-project adapter selection and
  decaying-baseline configuration.

### Phase Validation (243)

- `TaskScanner` — reads `tasks/` and cross-checks declared surfaces against the current
  codebase. Four-colour drift report: green / yellow / red / orange.

### Pending Attention Queue (244)

- `PendingAttentionQueue` — persisted, deduplicated queue of discipline findings.
  `Finding`, `FindingCategory`, `Severity` types.

### DisciplineEngine (245)

- `DisciplineEngine` actor — central coordinator. Runs all scanners, accumulates findings,
  integrates with the hook engine. Circuit breaker: 3 consecutive failures disable the
  engine for the session.

### Hook Integration (246–248)

- `SessionStart` hook event + system-reminder injection — top-3 findings surfaced at
  session open.
- `UserPromptSubmit` discipline check — flags unscoped feature requests without task files.
- `GitHookInstaller` — post-commit and pre-push hook installer / uninstaller.

### Manual Coverage (249–250)

- `ManualCoverageScanner` — enumerates user-facing surfaces via adapter regex patterns;
  reads `<!-- covers: ... -->` doc blocks; returns gaps.
- `ManualBaselineManager` + `ManualSectionTemplateWriter` — decaying baseline enforcement;
  template section writer for uncovered surfaces.

### Doc Reference Graph (251)

- `DocReferenceGraph` automatic mode — greps doc files for symbol-shaped identifiers;
  cross-checks against source symbol index; returns stale references.

### API & Guide Generation (252–253)

- `APIDocGenerator` — drives DocC (Swift) or rustdoc (Rust) for API doc regeneration.
- `DevGuideGenerator` — regenerates mechanical sections of `developer-guide.md` from
  the adapter; preserves prose outside `<!-- dev-guide:begin/end -->` markers.

### WHY-Comment Enforcement (254–255)

- `WhyCommentScanner` — trigger-pattern scanning with ±3-line comment check.
  `rationale-not-needed:` annotation suppresses individual triggers.
- `WHYCommentGate` + `OverrideAnnotationParser` — pre-commit gate blocks on missing
  WHY comments; parses override annotations.

### Prose Readability (256–257)

- `ProseReadabilityChecker` — Vale integration; dry-run mode for tests.
- `ValeStyleWriter` — writes Merlin Vale style files (readability, accept, passive-voice,
  weasel).
- `ProseGate` — pre-commit gate blocks doc files exceeding target Flesch-Kincaid grade.

### Override Audit (258)

- `OverrideAuditLog` — JSONL override log; weekly review adds
  `overrideAuditAccumulation` finding when any category exceeds 5 overrides/week.

### Project Skills (259–263)

- `/project:init` — scaffold a new project with full discipline support.
- `/project:task` — build an NNa/NNb task pair with structured questioning.
- `/project:revise` — scan for drift, present findings, apply patches.
- `/project:release` — consolidated release gate with 14-check checklist.
- `/project:adopt` — apply discipline to an existing project; first target: Merlin itself.

### Discipline UI (264)

- `PendingAttentionViewModel` — `@MainActor ObservableObject` backed by the queue.
- `PendingAttentionChipView` — compact count chip in the chat toolbar.
- `PendingAttentionPanelView` — expandable panel with per-finding dismiss affordances.

## Known Issues

- `DocReferenceGraph` automatic mode has a false-positive rate on short identifiers (< 4
  characters). Mitigated by minimum length heuristic; explicit mode (future) will be more
  precise.
- `ProseReadabilityChecker` requires `vale` to be installed as a dev tool. Graceful
  degradation: checker returns grade 0 (always passes) when `vale` is not found.
- `WhyCommentScanner` does not yet scan Rust test files — restricted to `*.swift` and
  `*.rs` in non-test directories.
- Skill files (259–263) require the `~/.merlin/skills/` directory to be writable. On
  sandboxed deployments the skills cannot be installed.

## Upgrade Notes

**From v2.1.0**: No breaking changes to existing v2.1.0 APIs. The v2.2 subsystem is additive.

To activate the Project Discipline Subsystem on your project:
1. Run `/project:adopt` in a Merlin session with your project open.
2. Follow the adoption report recommendations.
3. Run `/project:revise` to start working through the backlog.

The discipline subsystem is opt-in at the project level (`.merlin/project.toml` must exist).
Sessions on projects without `.merlin/project.toml` are unaffected.

**Build number**: 17 (was 16 in v2.1.0)
```

---

## Steps

After writing the above files, run in order:

```bash
# 1. Regenerate Xcode project
cd ~/Documents/localProject/merlin
xcodegen generate

# 2. Build and confirm version
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

Expected: **BUILD SUCCEEDED** and all phase 265a tests pass. No prior phase regresses.

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

## Commit

```bash
git add tasks/task-265b-v2-2-release.md \
    project.yml \
    RELEASE-v2.2.0.md
git commit -m "Phase 265b — Bump version to 2.2.0 (build 17)"
```

## Tag and Publish

```bash
git tag v2.2.0
git push && git push --tags

gh release create v2.2.0 \
    --repo j-zuilkowski/merlin \
    --title "v2.2.0 — Project Discipline Subsystem" \
    --notes-file RELEASE-v2.2.0.md \
    --latest
```
