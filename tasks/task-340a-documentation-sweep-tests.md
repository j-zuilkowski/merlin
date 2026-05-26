# Task 340a — Documentation Sweep Tests

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 339b complete: llama.cpp provider support and the sidebar slot status
panel have shipped.

Recommended execution model: GPT-5.3-Codex.

Task 338b and 339b update the docs directly attached to their features. This
task adds a final documentation drift gate across the repo so release-current
docs, generated docs, local-provider scripts, and eval scenario inventories do
not retain stale provider/slot descriptions.

Documentation scan completed before staging this task found these current docs
requiring coverage:

- `README.md`
- `FEATURES.md`
- `Merlin/Docs/UserGuide.md`
- `Merlin/Docs/DeveloperManual.md`
- `docs/developer-guide.md` (mechanical guide; regenerate/verify if generator
  metadata changes)
- `docs/local-provider-configs/README.md`
- `docs/local-provider-configs/RESULTS.md`
- `docs/local-provider-configs/smoke-test.sh`
- `docs/local-provider-configs/benchmark-throughput.sh`
- `merlin-eval/SURFACE-CENSUS.md`
- `merlin-eval/SURFACE-INVENTORY.md`
- `merlin-eval/scenarios/S9-panels.md`
- `merlin-eval/scenarios/S13-providers-connectors.md`
- `tasks/SURFACE-INVENTORY.md`

Historical release notes, old task files, and dated handoff snapshots may
retain historical references. The sweep should not rewrite them unless they are
being regenerated as living aggregate documentation.

TDD coverage:
  File 1 - `MerlinTests/Unit/DocumentationSweepTests.swift`:
    `testReleaseDocsMentionLlamaCppProvider` - README, FEATURES, UserGuide,
    DeveloperManual, and local-provider README mention llama.cpp/`llamacpp`.
    `testLocalProviderScriptsKnowLlamaCpp` - smoke and benchmark scripts include
    `llamacpp` and `http://localhost:8081/v1`.
    `testUserFacingDocsDoNotDescribeProviderHUDAsRoutingControl` - release
    user docs no longer instruct users to click ProviderHUD/top-of-chat provider
    routing.
    `testUserFacingDocsDescribeSlotStatusPanel` - UserGuide and FEATURES
    mention the sidebar slot status panel and `Not configured` rows.
    `testEvalCurrentDocsUseUpdatedProviderCounts` - current eval scenario and
    surface docs do not claim there are only 11 providers after llama.cpp lands.
    `testCurrentSurfaceDocsMentionSlotStatusPanel` - current surface docs cover
    SlotStatusPanel instead of current ProviderHUD routing status.

---

## Write to: MerlinTests/Unit/DocumentationSweepTests.swift

Use filesystem reads from the repository root. Keep the assertions textual and
targeted so historical docs are not over-constrained.

Recommended helper:

```swift
private func repoFile(_ path: String) throws -> String
```

The tests should explicitly distinguish release-current docs from historical
docs:

- Include: README, FEATURES, `Merlin/Docs`, `docs/local-provider-configs`,
  current eval scenarios/surface inventories.
- Exclude: `RELEASE-*`, dated handoffs, old task files except
  `tasks/SURFACE-INVENTORY.md`, and historical aggregate `tasks/ALL-TASKS.md`.

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```
Expected: BUILD FAILED with documentation sweep assertions identifying any
remaining stale docs.

## Commit
```bash
git add MerlinTests/Unit/DocumentationSweepTests.swift \
        tasks/task-340a-documentation-sweep-tests.md
git commit -m "Task 340a — documentation sweep tests (failing)"
```
