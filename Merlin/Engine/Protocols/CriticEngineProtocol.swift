import Foundation

protocol CriticEngineProtocol: Sendable {
    func evaluate(taskType: DomainTaskType, output: String, context: [Message]) async -> CriticResult
    /// Enhanced evaluation that cross-references written file contents.
    /// Default implementation forwards to the 3-param version (backward-compatible for mocks).
    func evaluate(taskType: DomainTaskType, output: String, context: [Message], writtenFiles: [String]) async -> CriticResult
}

extension CriticEngineProtocol {
    func evaluate(taskType: DomainTaskType, output: String, context: [Message], writtenFiles: [String]) async -> CriticResult {
        await evaluate(taskType: taskType, output: output, context: context)
    }
}

extension CriticEngine: CriticEngineProtocol {}
