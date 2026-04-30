# Phase 119b — LoRACoordinator

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 119a complete: LoRACoordinatorTests (failing) in place.

---

## Write to: Merlin/Engine/LoRACoordinator.swift

```swift
import Foundation

/// Decides when to trigger LoRA fine-tuning and prevents concurrent training runs.
/// Called from AgenticEngine.runLoop() after each performanceTracker.record() when
/// loraEnabled + loraAutoTrain are both true.
actor LoRACoordinator {

    // MARK: - State

    private(set) var isTraining: Bool = false
    private(set) var lastResult: LoRATrainingResult?

    // MARK: - Dependencies

    private let trainer: any LoRATrainable

    // MARK: - Init

    init(trainer: any LoRATrainable = LoRATrainer()) {
        self.trainer = trainer
    }

    // MARK: - Public API

    /// Called after every session record. Fetches the current training export; if the
    /// sample count meets the threshold and no training is already running, kicks off
    /// a background training task.
    func considerTraining(
        tracker: any ModelPerformanceTrackerProtocol,
        minSamples: Int,
        baseModel: String,
        adapterOutputPath: String,
        iterations: Int = 100
    ) async {
        guard !isTraining else { return }
        guard !baseModel.isEmpty else { return }

        let records = await tracker.exportTrainingData(minScore: 0.7)
        guard records.count >= minSamples else { return }

        isTraining = true

        Task.detached { [weak self] in
            guard let self else { return }
            let result = await self.trainer.train(
                records: records,
                baseModel: baseModel,
                adapterOutputPath: adapterOutputPath,
                iterations: iterations
            )
            await self.finishTraining(result: result)
        }
    }

    // MARK: - Private

    private func finishTraining(result: LoRATrainingResult) {
        lastResult = result
        isTraining = false
    }
}

// MARK: - LoRATrainable protocol (lets tests inject a stub trainer)

protocol LoRATrainable: Sendable {
    func train(records: [OutcomeRecord], baseModel: String,
               adapterOutputPath: String, iterations: Int) async -> LoRATrainingResult
}

extension LoRATrainer: LoRATrainable {}
```

---

## Edit: Merlin/Engine/AgenticEngine.swift — add loraCoordinator property and trigger

### 1. Add property near xcalibreClient

```swift
// After: var xcalibreClient: (any XcalibreClientProtocol)?
var loraCoordinator: LoRACoordinator?
```

### 2. Trigger after performanceTracker.record() at session end

```swift
// AFTER the performanceTracker.record(...) call:
if AppSettings.shared.loraEnabled, AppSettings.shared.loraAutoTrain,
   let coordinator = loraCoordinator {
    await coordinator.considerTraining(
        tracker: performanceTracker,
        minSamples: AppSettings.shared.loraMinSamples,
        baseModel: AppSettings.shared.loraBaseModel,
        adapterOutputPath: AppSettings.shared.loraAdapterPath
    )
}
```

---

## Edit: Merlin/App/AppState.swift — wire coordinator at init

```swift
// In AppState.init() or where engine is configured, after engine setup:
let loraCoordinator = LoRACoordinator()
engine.loraCoordinator = loraCoordinator
```

---

## Verify
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'LoRACoordinator.*passed|LoRACoordinator.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -20
```
Expected: BUILD SUCCEEDED; LoRACoordinatorTests → 4 pass; all prior tests pass; zero warnings.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/LoRACoordinator.swift \
        Merlin/Engine/AgenticEngine.swift \
        Merlin/App/AppState.swift
git commit -m "Phase 119b — LoRACoordinator (threshold-gated auto-train trigger, concurrent-safe)"
```
