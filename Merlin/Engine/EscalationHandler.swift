import Foundation

enum EscalationReason: Sendable {
    case iterationCap(loopCount: Int, lastObservation: String)
    case preflightOverflow(estimated: Int, budget: Int)
}

enum EscalationDecision: Sendable {
    case continueWith(replacementSteps: [PlanStep])
    case routeToProvider(providerID: String, reason: String)
    case stop(message: String)
}

actor EscalationHandler {

    private let planner: PlannerEngine
    private let registry: ProviderRegistry?
    private let maxRefinementsPerTurn: Int
    private var successfulRefinements = 0

    init(
        planner: PlannerEngine,
        registry: ProviderRegistry? = nil,
        maxRefinementsPerTurn: Int = 2
    ) {
        self.planner = planner
        self.registry = registry
        self.maxRefinementsPerTurn = max(0, maxRefinementsPerTurn)
    }

    func escalateOrStop(
        currentStep: PlanStep,
        reason: EscalationReason,
        context: [Message]
    ) async -> EscalationDecision {
        guard successfulRefinements < maxRefinementsPerTurn else {
            return .stop(message: stopMessage(
                reason: "refinement budget exhausted",
                suggestion: "reduce scope before retrying",
                context: context
            ))
        }

        let refineReason: RefineReason
        switch reason {
        case .iterationCap(let loopCount, let lastObservation):
            refineReason = .iterationCap(loopCount: loopCount, lastObservation: lastObservation)
        case .preflightOverflow(let estimated, let budget):
            refineReason = .budget(estimated: estimated, budget: budget)
        }

        let outcome = await planner.refineStep(currentStep, reason: refineReason, context: context)
        switch outcome {
        case .decomposed(let replacementSteps):
            successfulRefinements += 1
            return .continueWith(replacementSteps: replacementSteps)
        case .cannotDecompose(let explanation):
            if let registry {
                let orderedProviders = await registry.providersOrderedByBudget()
                if let provider = orderedProviders.reversed().first(where: { $0.budget.usableInputTokens >= currentStep.minContextRequired }) {
                    return .routeToProvider(providerID: provider.id, reason: explanation)
                }
                return .stop(message: "step requires \(currentStep.minContextRequired) tokens; no configured provider supports that budget")
            }
            let fallbackSteps = await planner.decompose(task: currentStep.description, context: context)
            if fallbackSteps.isEmpty == false {
                successfulRefinements += 1
                return .continueWith(replacementSteps: fallbackSteps)
            }
            return .stop(message: stopMessage(
                reason: explanation,
                suggestion: explanation,
                context: context
            ))
        }
    }

    private func stopMessage(reason: String, suggestion: String, context: [Message]) -> String {
        """
        ⛔ Cannot continue: \(reason). Suggested: \(suggestion). Progress so far:
        \(progressSummary(from: context))
        """
    }

    private func progressSummary(from messages: [Message]) -> String {
        let recent = messages.suffix(3)
        guard recent.isEmpty == false else {
            return "- no progress recorded"
        }
        return recent.enumerated().map { index, message in
            let text = message.content.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            let snippet = text.isEmpty ? "(empty)" : String(text.prefix(120))
            return "- \(index + 1). \(message.role.rawValue): \(snippet)"
        }.joined(separator: "\n")
    }
}
