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

### Task Validation (243)

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
