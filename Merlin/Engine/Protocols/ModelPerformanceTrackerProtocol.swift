import Foundation

protocol ModelPerformanceTrackerProtocol: Sendable {
    func record(modelID: String, taskType: DomainTaskType, signals: OutcomeSignals) async
    func successRate(for modelID: String, taskType: DomainTaskType) -> Double?
    func profile(for modelID: String) -> [ModelPerformanceProfile]
    func allProfiles() -> [ModelPerformanceProfile]
    func records(for modelID: String, taskType: DomainTaskType) async -> [OutcomeRecord]
    func exportTrainingData(minScore: Double) async -> [OutcomeRecord]
}

extension ModelPerformanceTracker: @preconcurrency ModelPerformanceTrackerProtocol {}
