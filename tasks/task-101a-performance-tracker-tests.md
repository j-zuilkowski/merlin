# Phase 101a — ModelPerformanceTracker Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 100b complete: AgenticEngine role slot routing in place.

New surface introduced in phase 101b:
  - `OutcomeSignals` struct — auto-collected session outcome data
  - `OutcomeRecord` struct — persisted single outcome (Codable)
  - `ModelPerformanceProfile` struct — rolling per-model × task-type profile
  - `Trend` enum — improving / stable / declining
  - `ModelPerformanceTracker` actor — records outcomes, returns calibrated success rates
  - 30-sample calibration minimum: `successRate()` returns nil below threshold
  - Profiles persisted at `~/.merlin/performance/<model-id>.json`

TDD coverage:
  File 1 — ModelPerformanceTrackerTests: record, successRate (nil below 30), isCalibrated, trend, profile

---

## Write to: MerlinTests/Unit/ModelPerformanceTrackerTests.swift

```swift
import XCTest
@testable import Merlin

final class ModelPerformanceTrackerTests: XCTestCase {

    private let taskType = DomainTaskType(
        domainID: "software", name: "code_generation", displayName: "Code Generation"
    )

    private func makeTracker() -> ModelPerformanceTracker {
        ModelPerformanceTracker(storageURL: URL(fileURLWithPath: "/tmp/merlin-tracker-test-\(UUID())"))
    }

    private func signals(stage1: Bool = true, diffAccepted: Bool = true,
                         corrected: Bool = false, retries: Int = 0) -> OutcomeSignals {
        OutcomeSignals(
            stage1Passed: stage1,
            stage2Score: stage1 ? 0.9 : 0.3,
            diffAccepted: diffAccepted,
            diffEditedOnAccept: false,
            criticRetryCount: retries,
            userCorrectedNextTurn: corrected,
            sessionCompleted: true,
            addendumHash: "abc123"
        )
    }

    // MARK: - Calibration threshold

    func testSuccessRateNilBelow30Samples() async {
        let tracker = makeTracker()
        let s = signals()
        for _ in 0..<29 {
            await tracker.record(modelID: "model-a", taskType: taskType, signals: s)
        }
        let rate = await tracker.successRate(for: "model-a", taskType: taskType)
        XCTAssertNil(rate, "Should return nil until 30 samples are collected")
    }

    func testSuccessRateNotNilAt30Samples() async {
        let tracker = makeTracker()
        let s = signals()
        for _ in 0..<30 {
            await tracker.record(modelID: "model-b", taskType: taskType, signals: s)
        }
        let rate = await tracker.successRate(for: "model-b", taskType: taskType)
        XCTAssertNotNil(rate)
    }

    func testSuccessRateReflectsOutcomes() async {
        let tracker = makeTracker()
        // 20 successes + 10 failures out of 30
        let good = signals(stage1: true, diffAccepted: true, corrected: false)
        let bad  = signals(stage1: false, diffAccepted: false, corrected: true)
        for _ in 0..<20 { await tracker.record(modelID: "model-c", taskType: taskType, signals: good) }
        for _ in 0..<10 { await tracker.record(modelID: "model-c", taskType: taskType, signals: bad) }
        let rate = await tracker.successRate(for: "model-c", taskType: taskType)!
        // Success rate should be > 0.5 (more successes than failures)
        XCTAssertGreaterThan(rate, 0.5)
        XCTAssertLessThan(rate, 1.0)
    }

    func testIsCalibrated() async {
        let tracker = makeTracker()
        let s = signals()
        for _ in 0..<29 {
            await tracker.record(modelID: "model-d", taskType: taskType, signals: s)
        }
        var profiles = await tracker.profile(for: "model-d")
        XCTAssertFalse(profiles.first?.isCalibrated ?? true)

        await tracker.record(modelID: "model-d", taskType: taskType, signals: s)
        profiles = await tracker.profile(for: "model-d")
        XCTAssertTrue(profiles.first?.isCalibrated ?? false)
    }

    func testProfilePerModelPerTaskType() async {
        let tracker = makeTracker()
        let taskType2 = DomainTaskType(domainID: "software", name: "refactoring", displayName: "Refactoring")
        let s = signals()
        for _ in 0..<30 {
            await tracker.record(modelID: "model-e", taskType: taskType, signals: s)
            await tracker.record(modelID: "model-e", taskType: taskType2, signals: s)
        }
        let profiles = await tracker.profile(for: "model-e")
        XCTAssertEqual(profiles.count, 2)
        XCTAssertTrue(profiles.contains(where: { $0.taskType.name == "code_generation" }))
        XCTAssertTrue(profiles.contains(where: { $0.taskType.name == "refactoring" }))
    }

    func testAddendumHashTrackedSeparately() async {
        let tracker = makeTracker()
        let v1 = OutcomeSignals(stage1Passed: true, stage2Score: 0.9,
                                diffAccepted: true, diffEditedOnAccept: false,
                                criticRetryCount: 0, userCorrectedNextTurn: false,
                                sessionCompleted: true, addendumHash: "hash-v1")
        let v2 = OutcomeSignals(stage1Passed: false, stage2Score: 0.3,
                                diffAccepted: false, diffEditedOnAccept: false,
                                criticRetryCount: 2, userCorrectedNextTurn: true,
                                sessionCompleted: false, addendumHash: "hash-v2")
        for _ in 0..<30 { await tracker.record(modelID: "model-f", taskType: taskType, signals: v1) }
        for _ in 0..<30 { await tracker.record(modelID: "model-f", taskType: taskType, signals: v2) }
        let allProfiles = await tracker.allProfiles()
        // Should have separate profiles for each addendum hash
        let forModel = allProfiles.filter { $0.modelID == "model-f" && $0.taskType.name == "code_generation" }
        XCTAssertEqual(forModel.count, 2)
        let v1Profile = forModel.first(where: { $0.addendumHash == "hash-v1" })
        let v2Profile = forModel.first(where: { $0.addendumHash == "hash-v2" })
        XCTAssertNotNil(v1Profile)
        XCTAssertNotNil(v2Profile)
        XCTAssertGreaterThan(v1Profile!.successRate, v2Profile!.successRate)
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
Expected: BUILD FAILED — `OutcomeSignals`, `OutcomeRecord`, `ModelPerformanceProfile`, `Trend`, `ModelPerformanceTracker` not defined.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/ModelPerformanceTrackerTests.swift
git commit -m "Phase 101a — ModelPerformanceTrackerTests (failing)"
```
