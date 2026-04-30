# Phase 113a — OutcomeRecord Persistence Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 112b complete: ragRerank + ragChunkLimit configurable.

Current state: ModelPerformanceProfile is already persisted to ~/.merlin/performance/<model>.json.
The raw OutcomeRecord array (records dict) is in-memory only — lost on every restart.
This is the V6 prerequisite: LoRA training needs accumulated raw records to build a training dataset.

New surface introduced in phase 113b:
  - `ModelPerformanceTracker` persists raw `OutcomeRecord` arrays alongside profiles
  - Records file: `~/.merlin/performance/records-<sanitised-model-id>.json`
  - `ModelPerformanceTracker.records(for:taskType:)` — returns persisted records for a model+taskType
  - `ModelPerformanceTracker.exportTrainingData(minScore:)` — returns all records above a quality
    threshold as instruction/response pairs for LoRA dataset export

TDD coverage:
  File 1 — OutcomeRecordPersistenceTests: records survive a tracker restart; records accumulate
            across multiple record() calls; exportTrainingData filters by minScore; empty export
            when no records meet threshold; records stored per model file

---

## Write to: MerlinTests/Unit/OutcomeRecordPersistenceTests.swift

```swift
import XCTest
@testable import Merlin

final class OutcomeRecordPersistenceTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("merlin-tracker-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Record persistence across restarts

    func testRecordsSurviveTrackerRestart() async {
        let taskType = DomainTaskType(domainID: "software", name: "code-edit", displayName: "Code Edit")
        let signals = makeSignals(stage1: true, stage2: 0.9, accepted: true)

        // First tracker instance — record an outcome
        let tracker1 = ModelPerformanceTracker(storageURL: tempDir)
        await tracker1.record(modelID: "model-a", taskType: taskType, signals: signals)

        // Second tracker instance with the same storageURL — simulates app restart
        let tracker2 = ModelPerformanceTracker(storageURL: tempDir)
        let records = await tracker2.records(for: "model-a", taskType: taskType)

        XCTAssertEqual(records.count, 1, "OutcomeRecord must survive a tracker restart")
        XCTAssertEqual(records.first?.modelID, "model-a")
    }

    func testRecordsAccumulateAcrossMultipleSessions() async {
        let taskType = DomainTaskType(domainID: "software", name: "code-edit", displayName: "Code Edit")
        let tracker = ModelPerformanceTracker(storageURL: tempDir)

        for _ in 0..<5 {
            await tracker.record(
                modelID: "model-b",
                taskType: taskType,
                signals: makeSignals(stage1: true, stage2: 0.8, accepted: true)
            )
        }

        let records = await tracker.records(for: "model-b", taskType: taskType)
        XCTAssertEqual(records.count, 5)
    }

    func testRecordsPersistedToCorrectFile() async {
        let taskType = DomainTaskType(domainID: "software", name: "code-edit", displayName: "Code Edit")
        let tracker = ModelPerformanceTracker(storageURL: tempDir)
        await tracker.record(
            modelID: "model-c",
            taskType: taskType,
            signals: makeSignals(stage1: true, stage2: 0.7, accepted: true)
        )

        let expectedFile = tempDir.appendingPathComponent("records-model-c.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedFile.path),
                      "Records must be saved to records-<model-id>.json")
    }

    func testRecordsSeparatedByModel() async {
        let taskType = DomainTaskType(domainID: "software", name: "code-edit", displayName: "Code Edit")
        let tracker = ModelPerformanceTracker(storageURL: tempDir)

        await tracker.record(modelID: "model-x", taskType: taskType,
                             signals: makeSignals(stage1: true, stage2: 0.9, accepted: true))
        await tracker.record(modelID: "model-y", taskType: taskType,
                             signals: makeSignals(stage1: false, stage2: 0.3, accepted: false))

        let xRecords = await tracker.records(for: "model-x", taskType: taskType)
        let yRecords = await tracker.records(for: "model-y", taskType: taskType)

        XCTAssertEqual(xRecords.count, 1)
        XCTAssertEqual(yRecords.count, 1)
        XCTAssertNotEqual(xRecords.first?.modelID, yRecords.first?.modelID)
    }

    // MARK: - exportTrainingData

    func testExportTrainingDataReturnsHighScoringRecords() async {
        let taskType = DomainTaskType(domainID: "software", name: "code-edit", displayName: "Code Edit")
        let tracker = ModelPerformanceTracker(storageURL: tempDir)

        // High score
        await tracker.record(modelID: "model-d", taskType: taskType,
                             signals: makeSignals(stage1: true, stage2: 1.0, accepted: true))
        // Low score
        await tracker.record(modelID: "model-d", taskType: taskType,
                             signals: makeSignals(stage1: false, stage2: 0.1, accepted: false))

        let exported = await tracker.exportTrainingData(minScore: 0.7)
        XCTAssertEqual(exported.count, 1, "Only records above minScore must be exported")
        XCTAssertGreaterThanOrEqual(exported.first?.score ?? 0, 0.7)
    }

    func testExportTrainingDataReturnsEmptyWhenNoneQualify() async {
        let taskType = DomainTaskType(domainID: "software", name: "code-edit", displayName: "Code Edit")
        let tracker = ModelPerformanceTracker(storageURL: tempDir)

        await tracker.record(modelID: "model-e", taskType: taskType,
                             signals: makeSignals(stage1: false, stage2: 0.2, accepted: false))

        let exported = await tracker.exportTrainingData(minScore: 0.7)
        XCTAssertTrue(exported.isEmpty)
    }
}

// MARK: - Helpers

private func makeSignals(stage1: Bool, stage2: Double, accepted: Bool) -> OutcomeSignals {
    OutcomeSignals(
        stage1Passed: stage1,
        stage2Score: stage2,
        diffAccepted: accepted,
        diffEditedOnAccept: false,
        criticRetryCount: 0,
        userCorrectedNextTurn: false,
        sessionCompleted: true,
        addendumHash: "00000000"
    )
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
Expected: BUILD FAILED — `ModelPerformanceTracker.records(for:taskType:)` and
`ModelPerformanceTracker.exportTrainingData(minScore:)` not defined.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/OutcomeRecordPersistenceTests.swift
git commit -m "Phase 113a — OutcomeRecordPersistenceTests (failing)"
```
