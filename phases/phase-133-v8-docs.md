# Phase 133 — V8 Documentation & Code Comment Update

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 132 complete: v7 docs and comments updated. All tests pass.

This is a documentation-only phase — no new symbols, no test changes.
Update every file introduced in phases 129–131 so that:
  1. All `///` doc-comments and `//` inline comments are complete and accurate.
  2. `architecture.md` cross-references, flow diagrams, and file-layout tables are accurate.
  3. `FEATURES.md` has a complete `/calibrate` entry.
  4. No stale references to "TODO", "Phase NNb", or placeholder text remain.

---

## Files to audit and update

### Merlin/Calibration/CalibrationTypes.swift
- `CalibrationCategory`: enum-level doc explaining the four categories and why they were chosen
  (reasoning and coding detect context/quality gaps; instruction-following detects truncation;
  summarization detects repetition).
- `CalibrationPrompt`: struct doc. Note `systemPrompt` is optional — most prompts use nil
  (the provider's default system prompt) to avoid skewing comparisons.
- `CalibrationResponse`: struct doc. Note `scoreDelta` is signed — negative means local beat
  the reference on that prompt.
- `CalibrationReport`:
  - Struct-level doc: one paragraph explaining what the report contains and how it is produced.
  - `overallDelta`: `///` — positive = reference is better; used by CalibrationAdvisor as the
    primary signal for contextLengthTooSmall.
  - `responsesByCategory`: `///` — convenience grouping used by CalibrationReportView.

### Merlin/Calibration/CalibrationSuite.swift
- `CalibrationSuite`: struct doc explaining the role of the suite and how `default` was designed.
- `default` static property: comment listing the prompt count per category (5 reasoning,
  5 coding, 4 instruction-following, 4 summarization = 18 total).
- Each prompt group (reasoning, coding, instruction-following, summarization): section comment
  explaining what signal that category is designed to surface.
- Individual prompts: each should already have descriptive text, but add a brief inline comment
  on any prompt whose signal-detection purpose is not obvious from its text alone.

### Merlin/Calibration/CalibrationRunner.swift
- `CalibrationRunner` actor: class-level doc explaining:
  - The closure injection pattern and why it is used (testability + decoupling from LLMProvider).
  - That `localProvider` and `referenceProvider` both receive the full `prompt.prompt` string
    (not the system prompt — the caller is responsible for building a full chat turn if needed).
  - That `scorer` is called once per response (local and reference scored separately).
- `ProviderClosure` / `ScorerClosure`: typealias docs.
- `run(suite:)`: doc explaining the TaskGroup parallelism — all prompts fire concurrently,
  results sorted by `prompt.id` for deterministic display.

### Merlin/Calibration/CalibrationAdvisor.swift
- `CategoryScores`: struct doc; note `delta` sign convention (positive = reference better).
- `CalibrationAdvisor`: struct-level doc listing all four detection algorithms with thresholds:
  - contextLengthTooSmall: overallDelta ≥ 0.40
  - temperatureUnstable: local score σ ≥ 0.22
  - maxTokensTooLow: ≥ 50% of responses have localLength / refLength < 0.30
  - repetitiveOutput: ≥ 50% of responses have trigram repetition ratio > 0.45
- Each threshold constant: `///` with the rationale for the chosen value.
- `analyze(responses:localModelID:localProviderID:)`:
  - Note the early return when `overallDelta < minActionableDelta`.
  - Comment each detection block with the advisory kind it produces.
- `categoryBreakdown(responses:)`: doc noting this is display-only — not used for advisory decisions.
- `repetitionRatio(in:)`: explain the trigram algorithm (sliding window of 3 consecutive words;
  ratio = 1 − uniqueTrigrams / totalTrigrams).

### Merlin/Calibration/CalibrationCoordinator.swift
- `CalibrationProgressInfo`: struct doc; note `fraction` is clamped implicitly by `Double(completed) / Double(total)`.
- `CalibrationSheet`: enum doc explaining the three-state machine:
  pickProvider → running → report.
- `CalibrationSheet: Identifiable` extension: comment explaining why a stable string ID is used
  (SwiftUI `.sheet(item:)` requires Identifiable; string prevents unnecessary re-presents).
- `CalibrationCoordinator` class:
  - Class-level doc: one paragraph on ownership (AppState holds it), sheet-state machine,
    and relationship to the existing applyAdvisory() pipeline.
  - `begin(localProviderID:localModelID:)`: doc — entry point from chat input bar /calibrate intercept.
  - `start(referenceProviderID:)`: doc — builds closures, runs suite, publishes progress state,
    then transitions to .report; catches errors by dismissing the sheet.
  - `applyAll()`: doc — iterates report advisories, calls appState.applyAdvisory for each,
    then dismisses. Uses `try?` so a single failure does not block the rest.
  - `registerSkill()`: doc — registers "calibrate" in ToolRegistry; called once at AppState init.
  - `availableReferenceProviders()`: doc — filters to non-local, configured providers only.
  - `makeProviderClosure(providerID:appState:)`: doc explaining the CompletionRequest construction
    (single non-streaming request, maxTokens: 1024, inference defaults applied).
  - `makeScorerClosure(appState:)`: doc — wraps CriticEngine.score; falls back to 0.5 on error
    so a scorer failure does not abort the entire suite run.
- `CalibrationError`: enum doc.

### Merlin/Views/Calibration/CalibrationProviderPickerView.swift
- View-level doc: note this is Sheet Step 1 of 3 in the /calibrate workflow.
- `onStart` closure: `///` — called with the selected providerID when user taps Start.
- The `.onChange(of: availableProviders)` and `.onAppear` blocks: inline comment explaining
  why both are needed (onAppear handles initial value; onChange handles async updates).

### Merlin/Views/Calibration/CalibrationProgressView.swift
- View-level doc: note this is Sheet Step 2 of 3.
- `.symbolEffect(.pulse)` usage: inline comment — requires macOS 14+.

### Merlin/Views/Calibration/CalibrationReportView.swift
- `CalibrationReportView`: view-level doc explaining it is Sheet Step 3 of 3, with the three
  visible regions (overall scores, category breakdown, advisory list) and the Apply All footer.
- `overallScoreSection`: comment noting that the gap label uses red for delta > 0.15 (same
  threshold as CalibrationAdvisor.minActionableDelta) and green otherwise.
- `categoryBreakdownSection`: comment noting `CalibrationCategory.allCases` iteration order is
  used so categories always appear in the same sequence regardless of which prompts ran.
- `CalibrationAdvisoryRow`: brief comment on why icon/color choices match PerformanceDashboard
  (consistent visual language across all advisory surfaces).
- `ScoreBar`: inline comment — `geo.size.width * score` assumes score is in [0,1].
- `CalibrationCategory.displayName` extension: note why this is a private extension rather than
  in the model layer (display strings belong in the view layer).

### Merlin/App/AppState.swift (additions from Phase 131b)
- `calibrationCoordinator`: `///` — lazy so CalibrationCoordinator can reference self via weak.
- `provider(for:)`: one-line doc.
- `configuredProviders`: one-line doc.
- `CalibrationCoordinator.registerSkill()` call site: inline comment explaining registration
  happens once at init, idempotent if called again.

---

## architecture.md updates

Verify the **Cross-Provider Calibration [v8]** section added in Phase 133 against the implementation:

1. **Flow diagram** — check all type names, method signatures, and threshold values match the code.
2. **Prompt battery table** — confirm 18 prompts, correct category counts (5/5/4/4).
3. **File layout** — confirm all 8 new files are listed under `Merlin/Calibration/` and
   `Merlin/Views/Calibration/`.
4. **Version summary line** — v8 line is correct (already updated).

If any discrepancy is found, correct the architecture.md entry. Do not invent new content.

---

## FEATURES.md updates

Add a `/calibrate` section (or expand the existing Model Control section if present).
Include:

```markdown
## Model Calibration (`/calibrate`)

Type `/calibrate` in the chat bar to benchmark the active local model against any configured
remote provider (Anthropic, OpenAI, DeepSeek, etc.).

**What it does:**
- Sends an 18-prompt battery (reasoning, coding, instruction-following, summarization) to both
  the local and reference provider simultaneously.
- Critic-scores every response pair and computes per-category and overall score gaps.
- Identifies up to four parameter issues: context length too small, temperature too high,
  output truncation, and repetitive output.
- Shows a report with a side-by-side score breakdown and one-tap "Apply All Suggestions"
  that routes fixes through the existing advisory pipeline (runtime reload where supported,
  restart instructions where not).

**What it cannot fix:**
- Model weight quality — use the LoRA self-training pipeline (`/lora`) for that.
- Provider network latency or API rate limits.
```

---

## Verify (no regressions)
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: **BUILD SUCCEEDED** — zero warnings, zero errors, all prior tests pass.

## Commit
```bash
git add Merlin/Calibration/CalibrationTypes.swift
git add Merlin/Calibration/CalibrationSuite.swift
git add Merlin/Calibration/CalibrationRunner.swift
git add Merlin/Calibration/CalibrationAdvisor.swift
git add Merlin/Calibration/CalibrationCoordinator.swift
git add Merlin/Views/Calibration/CalibrationProviderPickerView.swift
git add Merlin/Views/Calibration/CalibrationProgressView.swift
git add Merlin/Views/Calibration/CalibrationReportView.swift
git add Merlin/App/AppState.swift
git add architecture.md
git add FEATURES.md
git commit -m "Phase 133 — V8 docs + code comments: CalibrationSuite, CalibrationRunner, CalibrationAdvisor, CalibrationCoordinator, report views"
```
