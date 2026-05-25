# Task 340b — Documentation Sweep Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 340a complete: documentation sweep tests are failing on stale docs.

Recommended execution model: GPT-5.3-Codex.

This is the final documentation reconciliation after llama.cpp and the sidebar
slot status panel have both landed.

---

## Edit: README.md

- Add llama.cpp to local providers with router-mode, one-server general+vision
  pair notes.
- Update LoRA/GGUF deployment language to include llama.cpp.
- Remove or revise any main-screen provider-control wording that conflicts with
  the slot status panel.

## Edit: FEATURES.md

- Add llama.cpp to LLM Providers and Local Model Management.
- Update local model reload semantics: llama.cpp is router runtime load/unload
  when in router mode, restart-only in single-model mode.
- Document the sidebar slot status panel and the explicit-slot-only display
  rule.

## Edit: Merlin/Docs/UserGuide.md

- Add llama.cpp to provider setup and local provider table.
- Replace ProviderHUD/top-of-chat routing instructions with the lower-left slot
  status panel.
- Explain that configured providers do not mean configured slots.
- Explain that all four slot rows remain visible; unassigned rows read
  `Not configured`.
- Add llama.cpp LoRA serving path: MLX train -> fuse -> convert to GGUF -> serve
  through llama-server router.

## Edit: Merlin/Docs/DeveloperManual.md

- Add `LlamaCppModelManager` to provider/local model manager docs.
- Document router-mode endpoints, runtime load/unload, and single-model restart
  fallback.
- Document `SlotStatusPanel` and `SlotStatusResolver`.
- Update provider/default-provider counts and factory guidance.
- Keep `ProviderHUD` only as non-provider status if it still exists.

## Edit: docs/local-provider-configs/*

- `README.md`: add llama.cpp install, launch, model-pair, mmproj, LoRA,
  calibration, and memory guidance.
- `RESULTS.md`: add llama.cpp status as fresh result if calibrated; otherwise
  mark as pending and avoid claiming support quality not yet measured.
- `smoke-test.sh`: add `llamacpp` to usage, base URL dispatch, and `all`.
- `benchmark-throughput.sh`: add `llamacpp` to dispatch and `all`.

## Edit: Current Eval Docs

- `merlin-eval/SURFACE-CENSUS.md`: update provider count, local manager count,
  and current UI surface names.
- `merlin-eval/SURFACE-INVENTORY.md`: replace current ProviderHUD routing
  surface with SlotStatusPanel.
- `merlin-eval/scenarios/S9-panels.md`: verify SlotStatusPanel instead of
  ProviderHUD routing.
- `merlin-eval/scenarios/S13-providers-connectors.md`: update provider count and
  add assertion that provider inventory does not populate slot status rows
  unless slots are explicitly assigned.
- `tasks/SURFACE-INVENTORY.md`: update only if this living checklist is still
  treated as current.

Do not rewrite historical release notes, old task files, or dated handoff
snapshots. Those are historical records.

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Executed.*tests|BUILD' | tail
```
Expected: all unit tests pass, including `DocumentationSweepTests`.

```bash
rg -n "ProviderHUD|top-of-chat|top of the chat|11 defined providers|five local providers|other five" \
    README.md FEATURES.md Merlin/Docs docs/local-provider-configs merlin-eval tasks/SURFACE-INVENTORY.md
```
Expected: no stale current-doc hits. Historical or explicitly non-routing
ProviderHUD mentions are acceptable only when clearly labelled.

## Commit
```bash
git add README.md \
        FEATURES.md \
        Merlin/Docs/UserGuide.md \
        Merlin/Docs/DeveloperManual.md \
        docs/local-provider-configs/README.md \
        docs/local-provider-configs/RESULTS.md \
        docs/local-provider-configs/smoke-test.sh \
        docs/local-provider-configs/benchmark-throughput.sh \
        merlin-eval/SURFACE-CENSUS.md \
        merlin-eval/SURFACE-INVENTORY.md \
        merlin-eval/scenarios/S9-panels.md \
        merlin-eval/scenarios/S13-providers-connectors.md \
        tasks/SURFACE-INVENTORY.md \
        MerlinTests/Unit/DocumentationSweepTests.swift \
        tasks/task-340b-documentation-sweep.md
git commit -m "Task 340b — reconcile documentation after llama.cpp and slot status panel"
```
