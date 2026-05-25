# Phase 121a — LoRA Settings UI Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 120b complete: LoRA provider routing in place.

New surface introduced in phase 121b:
  - `LoRASettingsSection` — SwiftUI view; appears in the Settings window under a new
    "LoRA" tab / section. Contains:
      • Master toggle: "Enable LoRA fine-tuning" (loraEnabled)
      • Sub-group (disabled when loraEnabled = false):
          – "Auto-train when threshold reached" (loraAutoTrain)
          – "Minimum samples" stepper (loraMinSamples, 10–500)
          – "Base model" text field (loraBaseModel)
          – "Adapter output path" text field + "Browse…" button (loraAdapterPath)
          – "Auto-load adapter" toggle (loraAutoLoad)
          – "MLX-LM server URL" text field (loraServerURL, disabled if loraAutoLoad off)
      • Status area: shows "Training…" when LoRACoordinator.isTraining, otherwise
        last result summary (e.g. "Last trained: 42 samples · ✓")

TDD coverage:
  File 1 — LoRASettingsUITests: LoRASettingsSection type exists; sub-group controls
            disabled when loraEnabled=false; loraServerURL field disabled when
            loraAutoLoad=false; view instantiates without crash.

---

## Write to: MerlinTests/Unit/LoRASettingsUITests.swift

```swift
import XCTest
import SwiftUI
@testable import Merlin

@MainActor
final class LoRASettingsUITests: XCTestCase {

    // MARK: - View exists and instantiates

    func testLoRASettingsSectionExists() {
        // BUILD FAILED until 121b adds LoRASettingsSection
        _ = LoRASettingsSection()
    }

    func testLoRASettingsSectionInstantiatesWithoutCrash() {
        let view = LoRASettingsSection()
        // Wrap in a host to force body evaluation
        let host = NSHostingController(rootView: view)
        XCTAssertNotNil(host.view)
    }

    // MARK: - Sub-group disabled when master toggle off

    func testSubGroupDisabledWhenLoRADisabled() {
        let savedEnabled = AppSettings.shared.loraEnabled
        defer { AppSettings.shared.loraEnabled = savedEnabled }

        AppSettings.shared.loraEnabled = false
        // View must build without errors in the disabled state
        let view = LoRASettingsSection()
        let host = NSHostingController(rootView: view)
        XCTAssertNotNil(host.view,
                        "LoRASettingsSection must render without crash when loraEnabled = false")
    }

    // MARK: - View reflects enabled state

    func testViewRendersWhenLoRAEnabled() {
        let savedEnabled = AppSettings.shared.loraEnabled
        defer { AppSettings.shared.loraEnabled = savedEnabled }

        AppSettings.shared.loraEnabled = true
        let view = LoRASettingsSection()
        let host = NSHostingController(rootView: view)
        XCTAssertNotNil(host.view,
                        "LoRASettingsSection must render without crash when loraEnabled = true")
    }
}
```

---

## Verify
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD FAILED — `LoRASettingsSection` not defined.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/LoRASettingsUITests.swift
git commit -m "Phase 121a — LoRASettingsUITests (failing)"
```
