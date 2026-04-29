import Foundation

protocol PlannerEngineProtocol: Sendable {
    func classify(message: String, domain: any DomainPlugin) async -> ClassifierResult
    func decompose(task: String, context: [Message]) async -> [PlanStep]
}

extension PlannerEngine: PlannerEngineProtocol {}
