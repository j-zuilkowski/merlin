import Foundation

enum EscalationReason: Sendable {
    case iterationCap(loopCount: Int, lastObservation: String)
    case preflightOverflow(estimated: Int, budget: Int)
    /// The model exhausted its critic-correction retry budget and still could not
    /// produce a result the critic accepts. The correction is routed to a stronger
    /// provider rather than abandoned.
    case criticExhausted(reason: String)
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
    /// Provider IDs an escalation may route to — the providers actually wired to a
    /// slot, hence configured and reachable. The registry also lists providers that
    /// are merely *configured* (e.g. a `vllm` entry whose server is not running);
    /// routing an escalation to one of those just kills the turn. Empty = no filter
    /// (preserves behaviour for callers that don't supply it, e.g. unit tests).
    private let viableProviderIDs: Set<String>
    /// The engine-designated stronger provider (the reason slot's assignment, e.g.
    /// `deepseek:deepseek-v4-pro`). A capability escalation (critic/refinement
    /// exhaustion) routes here first — `providersOrderedByBudget()` ranks by
    /// context window, not capability, so a local model loaded at a large context
    /// would otherwise out-rank a stronger remote model and the escalation would
    /// just route back to the local backend. `nil` disables the preference.
    private let preferredEscalationProviderID: String?
    private var escalationAttempts = 0
    private var routedProviderIDs: Set<String> = []

    init(
        planner: PlannerEngine,
        registry: ProviderRegistry? = nil,
        maxRefinementsPerTurn: Int = 2,
        viableProviderIDs: Set<String> = [],
        preferredEscalationProviderID: String? = nil
    ) {
        self.planner = planner
        self.registry = registry
        self.maxRefinementsPerTurn = max(0, maxRefinementsPerTurn)
        self.viableProviderIDs = viableProviderIDs
        self.preferredEscalationProviderID = preferredEscalationProviderID
    }

    /// True when `id` is an allowed escalation target (wired to a slot), or when no
    /// viability filter was supplied.
    private func isViable(_ id: String) -> Bool {
        viableProviderIDs.isEmpty || viableProviderIDs.contains(id)
    }

    /// The strongest provider (highest budget) wired to a slot and not yet routed
    /// to this turn — the escalation target. `nil` when none remain.
    /// `providersOrderedByBudget()` is sorted largest-budget-first, so `first`
    /// (not `reversed().first`) yields the strongest provider.
    private func strongestUnusedViableProvider() async -> String? {
        guard let registry else { return nil }
        let ordered = await registry.providersOrderedByBudget()
        return ordered.first(where: {
            routedProviderIDs.contains($0.id) == false && isViable($0.id)
        })?.id
    }

    /// The target for a *capability* escalation (critic/refinement exhaustion).
    /// When a designated stronger provider exists, escalate to it — once. If it
    /// has already been tried, return `nil` (stop) rather than downgrade to a
    /// weaker provider: routing "down" after the strong model failed is pointless
    /// and risks landing on a modelless local backend. Only when there is no
    /// designated provider does it fall back to the strongest viable by budget.
    private func capabilityEscalationTarget() async -> String? {
        if let preferred = preferredEscalationProviderID {
            return routedProviderIDs.contains(preferred) ? nil : preferred
        }
        return await strongestUnusedViableProvider()
    }

    func escalateOrStop(
        currentStep: PlanStep,
        reason: EscalationReason,
        context: [Message]
    ) async -> EscalationDecision {
        guard escalationAttempts < maxRefinementsPerTurn else {
            // Refinement budget spent. Before giving up, escalate to a stronger
            // provider not yet tried this turn — a stalled local model often
            // succeeds on a remote model that doesn't malform tool calls. Stop
            // only when no viable stronger provider remains.
            if let provider = await capabilityEscalationTarget() {
                routedProviderIDs.insert(provider)
                escalationAttempts += 1
                return .routeToProvider(
                    providerID: provider,
                    reason: "refinement budget exhausted — escalating to a stronger model")
            }
            return .stop(message: stopMessage(
                reason: "refinement budget exhausted",
                suggestion: "reduce scope before retrying",
                context: context
            ))
        }

        // Critic exhaustion is not a planning/budget problem — the model simply was
        // not capable enough. Skip step refinement and route the correction to the
        // designated stronger provider (the reason slot — a capable remote model),
        // falling back to the strongest viable provider by budget.
        if case .criticExhausted(let why) = reason {
            if let provider = await capabilityEscalationTarget() {
                routedProviderIDs.insert(provider)
                escalationAttempts += 1
                return .routeToProvider(providerID: provider,
                                        reason: "critic unsatisfied: \(why)")
            }
            return .stop(message: stopMessage(
                reason: "critic could not be satisfied: \(why)",
                suggestion: "no stronger provider available to escalate to",
                context: context
            ))
        }

        let refineReason: RefineReason
        switch reason {
        case .iterationCap(let loopCount, let lastObservation):
            refineReason = .iterationCap(loopCount: loopCount, lastObservation: lastObservation)
        case .preflightOverflow(let estimated, let budget):
            refineReason = .budget(estimated: estimated, budget: budget)
        case .criticExhausted:
            refineReason = .iterationCap(loopCount: 0, lastObservation: "")  // unreachable
        }

        let outcome = await planner.refineStep(currentStep, reason: refineReason, context: context)
        switch outcome {
        case .decomposed(let replacementSteps):
            escalationAttempts += 1
            return .continueWith(replacementSteps: replacementSteps)
        case .cannotDecompose(let explanation):
            // The step can't be split — hand off to a stronger provider. Prefer the
            // designated reason slot (a capable remote model with a large context,
            // so it satisfies a context-overflow escalation too); fall back to the
            // strongest viable provider by budget. Routing by raw budget alone
            // picked a bare backend id whose config had no model set — the request
            // then went out as the provider id and the backend rejected it.
            if registry != nil {
                if let provider = await capabilityEscalationTarget() {
                    routedProviderIDs.insert(provider)
                    escalationAttempts += 1
                    return .routeToProvider(providerID: provider, reason: explanation)
                }
                return .stop(message: "step requires \(currentStep.minContextRequired) tokens; no configured provider supports that budget")
            }
            let fallbackSteps = await planner.decompose(task: currentStep.description, context: context)
            if fallbackSteps.isEmpty == false {
                escalationAttempts += 1
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
