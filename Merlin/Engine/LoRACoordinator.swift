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
