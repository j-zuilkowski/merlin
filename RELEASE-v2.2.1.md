# Merlin v2.2.1 - Project Discipline Remediation

Released: 2026-05-15

## Summary

v2.2.1 - Project Discipline remediation. Wires the v2.2 discipline subsystem into the
running app and fixes correctness bugs found in code review.

## What's new

- **The discipline subsystem is now live in the app (phase 272).** `AppState` builds a
  `DisciplineEngine` and a `PendingAttentionViewModel` at init, installs the seed
  adapters into `~/.merlin/adapters`, runs the `SessionStart` hook to surface the top
  findings at session open, and runs a discipline scan after every turn. `ChatView`
  shows the pending-attention chip in the chat header. In v2.2.0 the subsystem shipped
  but never executed.

## Internal changes

- **Finding idempotency (phase 266).** `Finding` gains a content-derived `dedupKey`
  (category + summary). `PendingAttentionQueue` is re-keyed by it, so a re-scan of an
  unchanged project collapses onto existing queue entries instead of growing
  `pending.json` without bound.
- **Doc-reference accuracy (phase 267).** `DisciplineEngine` no longer emits a stale
  finding for every healthy doc reference. `DocReferenceGraph.danglingReferences`
  reports only doc mentions of code symbols that do not exist in the source tree.
- **Scanner accuracy (phase 268).** `PhaseScanner` now excludes test targets
  (`MerlinTests` and friends), so public test symbols no longer produce spurious
  "undocumented" findings. `WhyCommentScanner` skips trigger patterns that appear only
  inside comments or string literals, removing false-positive pre-commit blocks.
  `DocReferenceGraph` associates each reference with the heading it appears under.
- **Adapter-key consistency (phase 269).** `AdapterRegistry.loadFromDirectory` registers
  adapters under their adapter-key (`swift-xcode`, `rust-cargo`) so
  `adapter(for: config.adapter)` resolves for real projects.
- **Prose readability (phase 270).** The Vale style file uses Vale's real `readability`
  rule, the checker parses Vale's actual JSON output, and `DisciplineEngine` now runs
  the prose checker over project docs.
- **Process and git-hook safety (phase 271).** `GitHookInstaller` refuses to clobber a
  pre-existing non-Merlin hook. `APIDocGenerator` and `ProseReadabilityChecker` gain
  process timeouts so a hung child cannot stall the app. `OverrideAuditLog` no longer
  force-unwraps.

## Migration

No migration required. v2.2.1 is a remediation release over v2.2.0 - all changes are
internal correctness fixes plus the app wiring that activates the existing v2.2
subsystem. Projects without a `.merlin/` directory are unaffected, exactly as in v2.2.0.

**Build number**: 18 (was 17 in v2.2.0).
