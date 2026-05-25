# Task 283b — Local Model Picker

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 283a complete: failing test for the `allSlotPickerEntries` local-model contract.

After this task, a local runner's individual loaded models are selectable from both
the role-slot picker and the chat-screen provider picker, the model list refreshes when
either picker opens, and Merlin never sends the bare backend id as a model name.

---

## Edit

### 1. `Merlin/Providers/ProviderConfig.swift` — `allSlotPickerEntries`

Change the per-provider loop (currently ~`:337-358`): for an enabled provider, decide
its entries by:

- **Local provider** (`config.isLocal`) **with** `modelsByProviderID[config.id]`
  non-empty → emit **only** one virtual `SlotPickerEntry` per model
  (`id = "\(config.id):\(model)"`, `displayName = "\(displayName) — \(model)"`,
  `isVirtual = true`). Do **not** emit the plain base entry.
- **Otherwise** (remote provider, or local with no known models) → emit the plain base
  entry as today, followed by any virtual per-model entries (unchanged behaviour).

Keep the existing handling for the active-but-disabled provider, if any.

### 2. `Merlin/Views/ProviderHUD.swift` — enumerate per-model entries

- Replace the `registry.providers.filter { … }` iteration with
  `registry.allSlotPickerEntries` (the same source the role-slot picker uses). Render
  one button per `SlotPickerEntry`; the button label is the entry's `displayName`; the
  selected/checked entry is the one whose id equals `appState.activeProviderID`.
- On tap, set `appState.activeProviderID = entry.id` (a plain id or a virtual
  `"backend:model"` id — both already resolve correctly downstream).
- When the popover opens, refresh the model list: `task` /`onAppear` on the popover
  content runs `Task { await registry.fetchAllModels() }`. Non-blocking — the list
  updates in place via the `@Published modelsByProviderID`.
- Empty-state: a local backend with no known models still shows its plain base entry
  (per edit 1); give that entry a hint in the HUD — e.g. a subtitle "no models loaded"
  — so the user knows to start/refresh the runner. Keep this minimal.

### 3. `Merlin/Views/Settings/RoleSlotSettingsView.swift` — refresh on appear

- Add `.onAppear { Task { await registry.fetchAllModels() } }` (or `.task { … }`) to
  the view, so opening "Providers & Slots" picks up a runner started after launch
  without the manual "Refresh Models" button.

### 4. Update `MerlinTests/Unit/SlotPickerEntriesTests.swift`

The `allSlotPickerEntries` contract changed for local-with-models. Update any assertion
that expected a *plain base entry for a local provider that has loaded models* — under
the new contract such a provider yields virtual entries only. Assertions about remote
providers, local-without-models, ordering of remote base-vs-virtual, and display names
are unchanged. List the file in the commit.

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

Expected: **BUILD SUCCEEDED**; all task 283a tests pass; updated `SlotPickerEntriesTests`
pass; no prior task regresses.

**Manual UI check** (required — this task is mostly view wiring): build and launch the
app with LM Studio running and two models loaded. Open the chat provider picker
(`ProviderHUD`) — it must list the two LM Studio models as separate choices, not a
single "LM Studio". Open Settings → Providers & Slots — the slot pickers must show the
same per-model entries without a manual refresh. Selecting a local model and sending a
turn must hit that model (verify via the LM Studio server log / the model's behaviour).

## Commit

```bash
git add tasks/task-283b-local-model-picker.md \
    Merlin/Providers/ProviderConfig.swift \
    Merlin/Views/ProviderHUD.swift \
    Merlin/Views/Settings/RoleSlotSettingsView.swift \
    MerlinTests/Unit/SlotPickerEntriesTests.swift
git commit -m "Task 283b — Local model picker in chat HUD + slot picker; model-list refresh"
```

## Fixes

A local runner's individual loaded models are now selectable from the chat provider
picker and the role-slot picker; both refresh the model list on open. The bare local
base entry is no longer offered when real models are known, so Merlin never sends the
backend id (`"lmstudio"`) as a model name.

## Follow-up (not in this task)

`ProviderRegistry.fetchModels` uses `{baseURL}/models` (OpenAI standard) while
`LMStudioModelManager.loadedModels` uses `{baseURL}/api/v1/models` (LM Studio's
management API) — two different model-list sources. Standardising on the `/v1/models`
path is a separate small cleanup.
