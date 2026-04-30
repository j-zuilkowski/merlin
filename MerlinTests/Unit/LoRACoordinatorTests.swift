import XCTest
@testable import Merlin

// MARK: - Stub trainer that records call count without running a process

private final class StubLoRATrainer: @unchecked Sendable, LoRATrainable {
    nonisolated(unsafe) var trainCallCount = 0
    nonisolated(unsafe) var stubbedResult = LoRATrainingResult(
        sampleCount: 5, adapterPath: "/tmp/adapter", success: true, errorMessage: nil
    )

    func train(records: [OutcomeRecord], baseModel: String,
               adapterOutputPath: String, iterations: Int) async -> LoRATrainingResult {
        trainCallCount += 1
        return stubbedResult
    }
}

// MARK: - Stub tracker that returns a fixed record list

private final class StubTracker: ModelPerformanceTrackerProtocol, @unchecked Sendable {
    nonisolated(unsafe) var exportedRecords: [OutcomeRecord] = []

    func record(modelID: String, taskType: DomainTaskType, signals: OutcomeSignals) async {}
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
        stubTracker.set(records: (1...3).map { makeRecord(n: $0) })
        let coordinator = LoRACoordinator(trainer: stubTrainer)

        await coordinator.considerTraining(
            tracker: stubTracker,
            minSamples: 5,
            baseModel: "mlx-community/test",
            adapterOutputPath: "/tmp/adapter"
        )
        // Give any potential background task time to fire
        try? await Task.sleep(nanoseconds: 50_000_000)

        let callCount = stubTrainer.trainCallCount
        XCTAssertEqual(callCount, 0, "Training must not fire when record count < minSamples")
    }

    // MARK: - Fires at threshold

    func testConsiderTrainingFiresAtThreshold() async {
        let stubTrainer = StubLoRATrainer()
        let stubTracker = StubTracker()
        stubTracker.set(records: (1...5).map { makeRecord(n: $0) })
        let coordinator = LoRACoordinator(trainer: stubTrainer)

        await coordinator.considerTraining(
            tracker: stubTracker,
            minSamples: 5,
            baseModel: "mlx-community/test",
            adapterOutputPath: "/tmp/adapter"
        )
        // Wait for background task
        try? await Task.sleep(nanoseconds: 100_000_000)

        let callCount = stubTrainer.trainCallCount
        XCTAssertEqual(callCount, 1, "Training must fire when record count >= minSamples")
    }

    // MARK: - Does not fire concurrently

    func testConsiderTrainingDoesNotFireWhenAlreadyTraining() async {
        let stubTrainer = StubLoRATrainer()
        let stubTracker = StubTracker()
        stubTracker.set(records: (1...10).map { makeRecord(n: $0) })
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

        let callCount = stubTrainer.trainCallCount
        XCTAssertLessThanOrEqual(callCount, 1,
                                 "Concurrent training runs must be prevented by isTraining guard")
    }

    // MARK: - lastResult set after training

    func testLastResultPopulatedAfterTraining() async {
        let stubTrainer = StubLoRATrainer()
        let stubTracker = StubTracker()
        stubTracker.set(records: (1...5).map { makeRecord(n: $0) })
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
