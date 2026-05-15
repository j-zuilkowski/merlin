# Phase 283a — Local Model Picker Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
v2.2.3 released.

A local runner (LM Studio, Ollama, …) serves multiple models from one endpoint. Merlin
already supports this via virtual provider IDs (`"backendID:modelID"`):
`ProviderRegistry.allSlotPickerEntries` emits one virtual entry per model in
`modelsByProviderID[id]`, and `provider(for:)` resolves a virtual ID to an
`OpenAICompatibleProvider` carrying the real model name. The role-slot picker
(`RoleSlotSettingsView`) already uses `allSlotPickerEntries`.

Three gaps remain:

1. For a **local** provider, `allSlotPickerEntries` still emits the plain base entry
   *alongside* the per-model virtual entries. Selecting the base entry sends
   `"model": "lmstudio"` (the config `id`) on the wire — the base local config's
   `model` field is empty. The base entry must not be offered when real models are
   known.
2. The chat-screen provider picker (`ProviderHUD`) iterates `registry.providers` —
   plain configs only — so it never offers per-model entries for local runners.
3. `modelsByProviderID` is fetched only at app launch and via a manual "Refresh
   Models" button, so a runner started after Merlin shows no models until relaunch.

New surface introduced in phase 283b:
  - `ProviderRegistry.allSlotPickerEntries` — changed contract: a **local** provider
    whose `modelsByProviderID[id]` is non-empty contributes **only** its per-model
    virtual entries (no plain base entry). Remote providers, and local providers with
    no known models, are unchanged (plain base entry, plus virtual entries if any).
  - `ProviderHUD` enumerates `registry.allSlotPickerEntries`; selecting an entry sets
    `activeProviderID` to that entry's id (plain or virtual). The picker refreshes the
    model list (`registry.fetchAllModels()`) when it opens.
  - `RoleSlotSettingsView` refreshes the model list when it appears.

TDD coverage:
  File 1 — `MerlinTests/Unit/LocalModelPickerEntriesTests.swift`: the changed
    `allSlotPickerEntries` contract — local + models ⇒ virtual-only; local + no models
    ⇒ plain base entry; remote ⇒ plain base entry (unchanged).

The `ProviderHUD` enumeration and the open/appear refresh are SwiftUI view wiring;
they are verified by the 283b build plus the manual launch check in 283b.

---

## Write to: MerlinTests/Unit/LocalModelPickerEntriesTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class LocalModelPickerEntriesTests: XCTestCase {

    /// A local provider with loaded models must contribute ONLY per-model virtual
    /// entries — no plain base entry whose id equals the bare backend id.
    func testLocalProviderWithModelsYieldsOnlyVirtualEntries() {
        let registry = ProviderRegistry()
        registry.setEnabled(true, for: "lmstudio")
        registry.modelsByProviderID["lmstudio"] = ["qwen/qwen3.6-27b",
                                                   "qwen2.5-vl-72b-instruct"]

        let lmEntries = registry.allSlotPickerEntries.filter {
            $0.id == "lmstudio" || $0.id.hasPrefix("lmstudio:")
        }

        XCTAssertFalse(lmEntries.contains { $0.id == "lmstudio" },
            "the bare base entry must not be offered when models are known")
        XCTAssertEqual(Set(lmEntries.map(\.id)),
                       ["lmstudio:qwen/qwen3.6-27b", "lmstudio:qwen2.5-vl-72b-instruct"],
                       "one virtual entry per loaded model, no base entry")
        XCTAssertTrue(lmEntries.allSatisfy { $0.isVirtual },
                      "every local entry must be a virtual per-model entry")
    }

    /// A local provider with no known models keeps its plain base entry so the user
    /// can still see the backend and trigger a refresh.
    func testLocalProviderWithoutModelsYieldsBaseEntry() {
        let registry = ProviderRegistry()
        registry.setEnabled(true, for: "lmstudio")
        registry.modelsByProviderID["lmstudio"] = []

        let lmEntries = registry.allSlotPickerEntries.filter {
            $0.id == "lmstudio" || $0.id.hasPrefix("lmstudio:")
        }

        XCTAssertEqual(lmEntries.map(\.id), ["lmstudio"],
            "with no known models, exactly the plain base entry is offered")
        XCTAssertFalse(lmEntries[0].isVirtual)
    }

    /// A remote provider always keeps its plain base entry — its base config carries a
    /// real model name. (Behaviour unchanged by phase 283b.)
    func testRemoteProviderKeepsBaseEntry() {
        let registry = ProviderRegistry()
        registry.setEnabled(true, for: "deepseek")

        let entries = registry.allSlotPickerEntries.filter { $0.id == "deepseek" }
        XCTAssertEqual(entries.count, 1,
            "a remote provider contributes its plain base entry")
        XCTAssertFalse(entries[0].isVirtual)
    }
}
```

(If `ProviderRegistry`'s test-construction or `modelsByProviderID` mutation differs
from what is shown, mirror the setup used by `MerlinTests/Unit/SlotPickerEntriesTests.swift`.)

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

Expected: **BUILD SUCCEEDED**, but `testLocalProviderWithModelsYieldsOnlyVirtualEntries`
**FAILS at runtime** — `allSlotPickerEntries` currently still emits the plain `lmstudio`
base entry alongside the virtual ones. (`testLocalProviderWithoutModelsYieldsBaseEntry`
and `testRemoteProviderKeepsBaseEntry` should already pass.)

Run `xcodegen generate` if the new test file is not picked up — the `MerlinTests`
sources are a directory glob and a new file must be registered in the project.

## Commit

```bash
git add phases/phase-283a-local-model-picker-tests.md \
    MerlinTests/Unit/LocalModelPickerEntriesTests.swift \
    Merlin.xcodeproj/project.pbxproj
git commit -m "Phase 283a — LocalModelPickerEntriesTests (failing)"
```
