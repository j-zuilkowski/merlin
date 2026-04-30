# Phase 119a — LoRACoordinator Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 118b complete: LoRATrainer in place.

Current state: Nothing triggers LoRATrainer automatically. Phase 119b introduces
LoRACoordinator — the piece that checks record count after each session, decides whether
to train, prevents concurrent training runs, and notifies when training completes.

New surface introduced in phase 119b:
  - `LoRACoordinator` — actor; holds LoRATrainer; wired into AgenticEngine
  - `LoRACoordinator.considerTraining(tracker:minSamples:baseModel:adapterOutputPath:) async`
      Checks exportTrainingData count; if >= minSamples and not already training, fires
      train() in a detached Task and sets isTraining = true until complete.
  - `LoRACoordinator.isTraining: Bool` — read by UI status indicator
  - `LoRACoordinator.lastResult: LoRATrainingResult?` — most recent training outcome
  - `AgenticEngine.loraCoordinator: LoRACoordinator?` — injected; called after each
      performanceTracker.record() when loraEnabled + loraAutoTrain are true.

TDD coverage:
  File 1 — LoRACoordinatorTests: considerTraining does not fire below threshold; fires at
            threshold; does not fire twice concurrently (isTraining guard); lastResult set
            after training; coordinator respects loraEnabled=false.

---

## Write to: MerlinTests/Unit/LoRACoordinatorTests.swift

```swift
import XCTest
@testable import Merlin

// MARK: - Stub trainer that records call count without running a process

private actor StubLoRATrainer {
    var trainCallCount = 0
    var stubbedResult = LoRATrainingResult(
        sampleCount: 5, adapterPath: "/tmp/adapter", success: true, errorMessage: nil
    )

    func train(records: [OutcomeRecord], baseModel: String,
               adapterOutputPath: String, iterations: Int) async -> LoRATrainingResult {
        trainCallCount += 1
        return stubbedResult
    }
}

// MARK: - Stub tracker that returns a fixed record list

private actor StubTracker: ModelPerformanceTrackerProtocol {
    var exportedRecords: [OutcomeRecord] = []

    func record(modelID: String, taskType: DomainTaskType, signals: OutcomeSignals,
                prompt: String, response: String) async {}
    func successRate(for modelID: String, taskType: DomainTaskType) -> Double? { nil }
    func profile(for modelID: String) -> [ModelPerformanceProfile] { [] }
    func allProfiles() -> [ModelPerformanceProfile] { [] }
    func records(for modelID: String, taskType: DomainTaskType) async -> [OutcomeRecord] { [] }
    func exportTrainingData(minScore: Double) async -> [OutcomeRecord] { exportedRecords }
}

private func makeRecord(n: Int) -> OutcomeRecord {
    OutcomeRecord(
        modelID: "m", taskType: DomainTaskType(domainID: "s", name: "e", displayName: "E"),
        score: 0.9, addendumHash: "0", timestamp: Date(),
        prompt: "prompt \(n)", response: "response \(n)"
    )
}

// MARK: - Tests

final class LoRACoordinatorTests: XCTestCase {

    // MARK: - Does not fire below threshold

    func testConsiderTrainingDoesNotFireBelowThreshold() async {
        // BUILD FAILED until 119b adds LoRACoordinator
        let stubTrainer = StubLoRATrainer()
        let stubTracker = StubTracker()
        // 3 records, threshold 5 — should not train
        await stubTracker.set(records: (1...3).map { makeRecord(n: $0) })
        let coordinator = LoRACoordinator(trainer: stubTrainer)

        await coordinator.considerTraining(
            tracker: stubTracker,
            minSamples: 5,
            baseModel: "mlx-community/test",
            adapterOutputPath: "/tmp/adapter"
        )
        // Give any potential background task time to fire
        try? await Task.sleep(nanoseconds: 50_000_000)

        let callCount = await stubTrainer.trainCallCount
        XCTAssertEqual(callCount, 0, "Training must not fire when record count < minSamples")
    }

    // MARK: - Fires at threshold

    func testConsiderTrainingFiresAtThreshold() async {
        let stubTrainer = StubLoRATrainer()
        let stubTracker = StubTracker()
        await stubTracker.set(records: (1...5).map { makeRecord(n: $0) })
        let coordinator = LoRACoordinator(trainer: stubTrainer)

        await coordinator.considerTraining(
            tracker: stubTracker,
            minSamples: 5,
            baseModel: "mlx-community/test",
            adapterOutputPath: "/tmp/adapter"
        )
        // Wait for background task
        try? await Task.sleep(nanoseconds: 100_000_000)

        let callCount = await stubTrainer.trainCallCount
        XCTAssertEqual(callCount, 1, "Training must fire when record count >= minSamples")
    }

    // MARK: - Does not fire concurrently

    func testConsiderTrainingDoesNotFireWhenAlreadyTraining() async {
        let stubTrainer = StubLoRATrainer()
        let stubTracker = StubTracker()
        await stubTracker.set(records: (1...10).map { makeRecord(n: $0) })
        let coordinator = LoRACoordinator(trainer: stubTrainer)

        // First call — starts training
        await coordinator.considerTraining(
            tracker: stubTracker, minSamples: 5,
            baseModel: "mlx-community/test", adapterOutputPath: "/tmp/adapter"
        )
        // Immediate second call — should be a no-op (isTraining guard)
        await coordinator.considerTraining(
            tracker: stubTracker, minSamples: 5,
            baseModel: "mlx-community/test", adapterOutputPath: "/tmp/adapter"
        )
        try? await Task.sleep(nanoseconds: 100_000_000)

        let callCount = await stubTrainer.trainCallCount
        XCTAssertLessThanOrEqual(callCount, 1,
                                 "Concurrent training runs must be prevented by isTraining guard")
    }

    // MARK: - lastResult set after training

    func testLastResultPopulatedAfterTraining() async {
        let stubTrainer = StubLoRATrainer()
        let stubTracker = StubTracker()
        await stubTracker.set(records: (1...5).map { makeRecord(n: $0) })
        let coordinator = LoRACoordinator(trainer: stubTrainer)

        await coordinator.considerTraining(
            tracker: stubTracker, minSamples: 5,
            baseModel: "mlx-community/test", adapterOutputPath: "/tmp/adapter"
        )
        try? await Task.sleep(nanoseconds: 150_000_000)

        let result = await coordinator.lastResult
        XCTAssertNotNil(result, "lastResult must be set after training completes")
        XCTAssertTrue(result?.success ?? false)
    }
}

// MARK: - StubTracker helper

extension StubTracker {
    func set(records: [OutcomeRecord]) {
        exportedRecords = records
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
Expected: BUILD FAILED — `LoRACoordinator` not defined.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/LoRACoordinatorTests.swift
git commit -m "Phase 119a — LoRACoordinatorTests (failing)"
```
