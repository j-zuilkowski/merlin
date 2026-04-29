import Foundation

protocol CriticEngineProtocol: Sendable {
    func evaluate(taskType: DomainTaskType, output: String, context: [Message]) async -> CriticResult
}

extension CriticEngine: CriticEngineProtocol {}
