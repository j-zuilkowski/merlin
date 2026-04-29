import Foundation

protocol ModelPerformanceTrackerProtocol: Sendable {
    func record(modelID: String, taskType: DomainTaskType, signals: OutcomeSignals) async
    func successRate(for modelID: String, taskType: DomainTaskType) -> Double?
    func profile(for modelID: String) -> [ModelPerformanceProfile]
    func allProfiles() -> [ModelPerformanceProfile]
}

extension ModelPerformanceTracker: @preconcurrency ModelPerformanceTrackerProtocol {}
