# Task 289 — v2.2.4 Release

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Tasks 283–288 complete: local model picker (283), tool-output cap (284), context
budget resolver (285), universal pre-flight guard (286), tool-requirement checker (287),
vision launchpad (288).

This task ships **v2.2.4** —  tasks 283–288 together. Follows `spec.md`
§ Versioning Policy. Do not start this task until  tasks 283–288 are all committed.

---

## Edit

- `project.yml`:
    - `MARKETING_VERSION: "2.2.3"` → `"2.2.4"`.
    - `CURRENT_PROJECT_VERSION: 20` → `21`.
    - Under `MerlinTests` → `resources:`, add `- path: RELEASE-v2.2.4.md`.
- **Version banners — every doc that carries one** (2.2.3 → 2.2.4, build 20 → 21):
    - `constitution.md`: `**Current version: 2.2.4** (build 21, tag v2.2.4)`.
    - `README.md`: `**Version 2.2.4** (build 21, tag v2.2.4)`.
    - `Merlin/Docs/UserGuide.md`: `**Version 2.2.4**`.
    - `Merlin/Docs/DeveloperManual.md`: `**Version 2.2.4**`.
    - `Requirements.md`: `Current version: **2.2.4** (build 21).`
- **Version tests:** delete `MerlinTests/Unit/AppVersion223Tests.swift` (asserts the old
  2.2.3/20 bundle version — would fail after the bump). Add `AppVersion224Tests.swift`
  (asserts 2.2.4 / 21) and `ReleaseNotes224Tests.swift` (`RELEASE-v2.2.4.md` exists with
  the four required sections). The `ReleaseNotes221Tests` / `222` / `223` stay — their
  release-notes files still exist and those tests still pass.
- `RELEASE-v2.2.4.md` — new file at the repo root, with this content:

  ```markdown
  # Merlin v2.2.4

  ## Summary

  v2.2.4 makes the provider context-overflow class of failures structurally
  impossible, adds first-use detection of missing external tools, lets you target a
  specific loaded local model per role slot, and introduces `vision.md` as the first
  artifact of the Project Discipline pipeline.

  ## What's new

  - **Context-overflow HTTP 400s are fixed at the source.** Three layers, end to end:
    tool output (`run_shell`, `read_file`) is capped before it can enter the model
    context (task 284); the per-request budget is discovered from the active model's
    real context window — queried live for local runners and OpenRouter, learned from
    the first 400 and persisted for commercial providers (task 285); and every LLM
    request on every engine path — planner, critic, subagents, summariser, memory,
    KAG, vision — is sized to fit the provider window before it is sent, not just the
    main turn loop (task 286).
  - **Local model picker.** When a local runner has several models loaded, each can be
    assigned to a role slot directly from the chat HUD and the slot picker (task 283).
  - **Missing-tool detection.** When a feature needs an external CLI tool that is not
    installed, Merlin detects it on first use and offers a one-click `brew install` for
    the Homebrew-safe tools, or shows the install command/URL for the rest — instead of
    a raw "command not found" (task 287).
  - **Vision launchpad.** `vision.md` is now the first artifact of the discipline
    pipeline — `vision → architecture → task → code`. `project:init` seeds it,
    `project:adopt` incorporates an existing one, `project:revise` grows and promotes
    ideas from it (task 288).

  ## Internal changes

  - New types: `ToolOutput`, `ContextBudgetResolver` / `ContextBudgetStore`,
    `PreflightGuard`, `ToolRequirement` / `ToolRequirements` / `ToolRequirementChecker`.
  - All 14 `provider.complete` send sites now route through `PreflightGuard`.
  - Learned context windows persist to `ProviderConfig.budget` in `providers.json` —
    the same field a manually-entered budget uses.

  ## Migration

  None. No configuration changes are required; context-budget discovery and tool
  detection are automatic.
  ```

- `Info.plist` needs no edit — `CFBundleShortVersionString` / `CFBundleVersion` use
  `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`.
- Run `xcodegen generate`.

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40

xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Then confirm no stale version string remains:

```bash
grep -rnE "2\.2\.3|build 20" README.md constitution.md Requirements.md \
    Merlin/Docs/UserGuide.md Merlin/Docs/DeveloperManual.md
```

Expected: **BUILD SUCCEEDED**; full suite green headless; `AppVersion224Tests` and
`ReleaseNotes224Tests` pass once the version is 2.2.4; the grep returns nothing.

## Commit

```bash
git add tasks/task-289-v2-2-4-release.md \
    project.yml \
    Merlin.xcodeproj/project.pbxproj \
    RELEASE-v2.2.4.md \
    constitution.md README.md Requirements.md \
    Merlin/Docs/UserGuide.md Merlin/Docs/DeveloperManual.md \
    MerlinTests/Unit/AppVersion224Tests.swift \
    MerlinTests/Unit/ReleaseNotes224Tests.swift
git rm MerlinTests/Unit/AppVersion223Tests.swift
git commit -m "Task 289 — Bump version to 2.2.4 (build 21)"
git tag v2.2.4
```

## Release — manual step (run yourself, not in the task batch)

Pushing and publishing a GitHub release are out-of-band actions. After the commit and
local tag above, run these yourself when ready:

```bash
git push && git push --tags
gh release create v2.2.4 --repo j-zuilkowski/merlin \
    --title "v2.2.4 — Context-overflow fix, tool detection, vision launchpad" \
    --notes-file RELEASE-v2.2.4.md --latest
```

The DMG (`scripts/package-dmg.sh`) reads the version from `project.yml` and produces
`dist/Merlin-2.2.4.dmg`.

## Fixes

Ships  tasks 283–288 as v2.2.4. The headline is the context-overflow HTTP 400 class
becoming structurally impossible (284 + 285 + 286): no tool result, and no LLM request
on any engine path, can exceed the active model's discovered context window.
