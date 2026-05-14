import Foundation

// MARK: - ComplexityTier

/// Domain-agnostic task complexity tiers.
enum ComplexityTier: String, Codable, Equatable, Sendable {
    case routine
    case standard
    case highStakes = "high-stakes"
}

// MARK: - ClassifierResult

struct ClassifierResult: Sendable {
    var needsPlanning: Bool
    var complexity: ComplexityTier
    var reason: String
}

// MARK: - RefineReason / RefineOutcome

enum RefineReason: Sendable {
    case iterationCap(loopCount: Int, lastObservation: String)
    case budget(estimated: Int, budget: Int)
    case explicit(String)
}

enum RefineOutcome: Sendable {
    case decomposed([PlanStep])
    case cannotDecompose(reason: String)
}

// MARK: - PlanStep

struct PlanStep: Sendable, Codable, Equatable {
    var description: String
    var successCriteria: [StepCriterion]
    var complexity: ComplexityTier
    var parallelSafe: Bool = false
    var tokenBudget: Int
    var requiresCritic: CriticMode = .optional
    var minContextRequired: Int

    static let defaultTokenBudget = ProviderBudget.conservative.usableInputTokens / 4

    var proseSummary: String {
        successCriteria.map { criterion in
            switch criterion {
            case .prose(let text):
                return text
            case .buildSucceeds:
                return "build succeeds"
            case .testsPass(let scheme):
                return scheme.map { "tests pass (\($0))" } ?? "tests pass"
            case .fileExists(let path):
                return "file exists: \(path)"
            case .regexMatch(let pattern, let target):
                return "regex match \(pattern) in \(target.rawValue)"
            case .shellExitZero(let command):
                return "shell exits zero: \(command)"
            }
        }.joined(separator: "; ")
    }

    init(
        description: String,
        successCriteria: [StepCriterion],
        complexity: ComplexityTier,
        parallelSafe: Bool = false,
        tokenBudget: Int = Self.defaultTokenBudget,
        requiresCritic: CriticMode = .optional,
        minContextRequired: Int? = nil
    ) {
        self.description = description
        self.successCriteria = successCriteria
        self.complexity = complexity
        self.parallelSafe = parallelSafe
        self.tokenBudget = tokenBudget
        self.requiresCritic = requiresCritic
        self.minContextRequired = minContextRequired ?? tokenBudget * 2
    }

    init(
        description: String,
        successCriteria: String,
        complexity: ComplexityTier,
        parallelSafe: Bool = false
    ) {
        self.init(
            description: description,
            successCriteria: [.prose(successCriteria)],
            complexity: complexity,
            parallelSafe: parallelSafe
        )
    }

    private enum CodingKeys: String, CodingKey {
        case description
        case step
        case successCriteria
        case success_criteria
        case complexity
        case parallelSafe
        case parallel_safe
        case tokenBudget
        case token_budget
        case requiresCritic
        case requires_critic
        case minContextRequired
        case min_context_required
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let description = try container.decodeIfPresent(String.self, forKey: .description)
            ?? container.decodeIfPresent(String.self, forKey: .step)
            ?? ""
        let criteria = try Self.decodeCriteria(from: container)
        let complexity = try container.decodeIfPresent(ComplexityTier.self, forKey: .complexity) ?? .standard
        let parallelSafe = try container.decodeIfPresent(Bool.self, forKey: .parallelSafe)
            ?? container.decodeIfPresent(Bool.self, forKey: .parallel_safe)
            ?? false
        let tokenBudget = try container.decodeIfPresent(Int.self, forKey: .tokenBudget)
            ?? container.decodeIfPresent(Int.self, forKey: .token_budget)
            ?? Self.defaultTokenBudget
        let requiresCritic = try container.decodeIfPresent(CriticMode.self, forKey: .requiresCritic)
            ?? container.decodeIfPresent(CriticMode.self, forKey: .requires_critic)
            ?? .optional
        let minContextRequired = try container.decodeIfPresent(Int.self, forKey: .minContextRequired)
            ?? container.decodeIfPresent(Int.self, forKey: .min_context_required)
            ?? tokenBudget * 2

        self.init(
            description: description,
            successCriteria: criteria,
            complexity: complexity,
            parallelSafe: parallelSafe,
            tokenBudget: tokenBudget,
            requiresCritic: requiresCritic,
            minContextRequired: minContextRequired
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(description, forKey: .description)
        try container.encode(successCriteria, forKey: .successCriteria)
        try container.encode(complexity, forKey: .complexity)
        try container.encode(parallelSafe, forKey: .parallelSafe)
        try container.encode(tokenBudget, forKey: .tokenBudget)
        try container.encode(requiresCritic, forKey: .requiresCritic)
        try container.encode(minContextRequired, forKey: .minContextRequired)
    }

    private static func decodeCriteria(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> [StepCriterion] {
        if let criteria = try? container.decode([StepCriterion].self, forKey: .successCriteria) {
            return criteria
        }
        if let criteria = try? container.decode([StepCriterion].self, forKey: .success_criteria) {
            return criteria
        }
        if let prose = try? container.decode(String.self, forKey: .successCriteria) {
            return [.prose(prose)]
        }
        if let prose = try? container.decode(String.self, forKey: .success_criteria) {
            return [.prose(prose)]
        }
        return []
    }
}

// MARK: - PlannerEngine

/// Planner layer:
///   1. execute-slot classifier decides needs_planning + complexity tier
///   2. If planning needed: orchestrate slot decomposes into steps
///   3. Tier overrides (#high-stakes, #routine, #standard) bypass classifier
actor PlannerEngine {

    private let executeProvider: any LLMProvider
    var orchestrateProvider: (any LLMProvider)?
    private let maxPlanRetries: Int

    init() {
        self.executeProvider = NullProvider()
        self.orchestrateProvider = nil
        self.maxPlanRetries = 2
    }

    init(orchestrateProvider: any LLMProvider) {
        self.executeProvider = NullProvider()
        self.orchestrateProvider = orchestrateProvider
        self.maxPlanRetries = 2
    }

    init(
        executeProvider: any LLMProvider,
        orchestrateProvider: (any LLMProvider)?,
        maxPlanRetries: Int = 2
    ) {
        self.executeProvider = executeProvider
        self.orchestrateProvider = orchestrateProvider
        self.maxPlanRetries = maxPlanRetries
    }

    // MARK: - Classification

    func classify(message: String, domain: any DomainPlugin) async -> ClassifierResult {
        let classifyStart = Date()
        let result: ClassifierResult

        if let override = parseTierOverride(from: message) {
            result = ClassifierResult(
                needsPlanning: override != .routine,
                complexity: override,
                reason: "declarative override"
            )
        } else {
            let lower = message.lowercased()
            var keywordMatch: ClassifierResult? = nil
            for keyword in domain.highStakesKeywords {
                guard keyword.count > 4 else { continue }
                if lower.contains(keyword.lowercased()) {
                    keywordMatch = ClassifierResult(
                        needsPlanning: true,
                        complexity: .highStakes,
                        reason: "high-stakes keyword: \(keyword)"
                    )
                    break
                }
            }
            if let keywordMatch {
                result = keywordMatch
            } else {
                result = await runClassifier(message: message)
            }
        }

        let ms = Date().timeIntervalSince(classifyStart) * 1000
        TelemetryEmitter.shared.emit("planner.classify", durationMs: ms, data: [
            "complexity": result.complexity.rawValue,
            "reason": result.reason,
            "used_llm": result.reason == "llm"
        ])
        return result
    }

    // MARK: - Decomposition

    func decompose(task: String, context: [Message]) async -> [PlanStep] {
        TelemetryEmitter.shared.emit("planner.decompose.start", data: [
            "task_length": task.count
        ])
        let decomposeStart = Date()
        guard let provider = orchestrateProvider else {
            TelemetryEmitter.shared.emit("planner.decompose.error", data: [
                "error_domain": "no_provider"
            ])
            return []
        }

        let usableInputBudget = PlanStep.defaultTokenBudget * 4
        let prompt = """
        Decompose the following task into concrete implementation steps.
        Respond with JSON only - no prose before or after:
        {
          "steps": [
            {
              "description": "...",
              "successCriteria": [
                { "kind": "prose", "value": "..." }
              ],
              "complexity": "routine|standard|high-stakes",
              "parallelSafe": true,
              "tokenBudget": 1234,
              "requiresCritic": "optional|required|skip",
              "minContextRequired": 1234
            }
          ]
        }

        Each step must include a concise description, structured success criteria, a complexity
        tier, a parallel-safety flag, an estimated token budget, critic policy, and the minimum
        usable input context required.

        Active usable input budget: \(usableInputBudget) tokens.
        Task: \(task)
        """

        var request = CompletionRequest(
            model: provider.resolvedModelID,
            messages: [Message(role: .user, content: .text(prompt), timestamp: Date())],
            thinking: nil
        )
        let inferenceDefaults = await MainActor.run { AppSettings.shared.inferenceDefaults }
        inferenceDefaults.apply(to: &request)

        for _ in 0..<max(1, maxPlanRetries) {
            do {
                var raw = ""
                let stream = try await provider.complete(request: request)
                for try await chunk in stream {
                    raw += chunk.delta?.content ?? ""
                }
                let steps = parseSteps(from: raw)
                if !steps.isEmpty {
                    for (index, step) in steps.enumerated() {
                        TelemetryEmitter.shared.emit("planner.step.executing", data: [
                            "step_index": index,
                            "total_steps": steps.count,
                            "complexity": step.complexity.rawValue,
                            "description_prefix": String(step.description.prefix(80))
                        ])
                    }
                    let ms = Date().timeIntervalSince(decomposeStart) * 1000
                    TelemetryEmitter.shared.emit("planner.decompose.complete", durationMs: ms, data: [
                        "step_count": steps.count
                    ])
                    return steps
                }
            } catch {
                TelemetryEmitter.shared.emit("planner.decompose.error", data: [
                    "error_domain": (error as NSError).domain,
                    "error_code": (error as NSError).code
                ])
                return []
            }
        }

        let ms = Date().timeIntervalSince(decomposeStart) * 1000
        TelemetryEmitter.shared.emit("planner.decompose.complete", durationMs: ms, data: [
            "step_count": 0
        ])
        return []
    }

    func refineStep(_ step: PlanStep, reason: RefineReason, context: [Message]) async -> RefineOutcome {
        TelemetryEmitter.shared.emit("planner.refine.start", data: [
            "reason": refineReasonLabel(reason)
        ])

        guard let provider = orchestrateProvider else {
            let message = "no orchestration provider"
            TelemetryEmitter.shared.emit("planner.refine.cannot_decompose", data: [
                "reason": message
            ])
            return .cannotDecompose(reason: message)
        }

        let usableInputBudget = PlanStep.defaultTokenBudget * 4
        let contextSummary = context.map { message -> String in
            let role = message.role.rawValue
            let text = message.content.plainText
            return "[\(role)] \(text)"
        }.joined(separator: "\n")

        let prompt = """
        Refine the following plan step into smaller substeps when possible.
        Return JSON only, with either:
        {
          "steps": [ ... ]
        }
        or:
        {
          "cannot_decompose": "reason"
        }

        Parent step:
        \(step.description)

        Token budget: \(step.tokenBudget)
        Minimum context required: \(step.minContextRequired)
        Success criteria: \(step.proseSummary)
        Refinement reason: \(refineReasonLabel(reason))

        Active usable input budget: \(usableInputBudget) tokens.
        Context:
        \(contextSummary)
        """

        var request = CompletionRequest(
            model: provider.resolvedModelID,
            messages: [Message(role: .user, content: .text(prompt), timestamp: Date())],
            thinking: nil
        )
        let inferenceDefaults = await MainActor.run { AppSettings.shared.inferenceDefaults }
        inferenceDefaults.apply(to: &request)

        do {
            var raw = ""
            let stream = try await provider.complete(request: request)
            for try await chunk in stream {
                raw += chunk.delta?.content ?? ""
            }

            let substeps = parseSteps(from: raw)
            let filtered = substeps.filter { $0.tokenBudget < step.tokenBudget }
            guard filtered.isEmpty == false, filtered.count == substeps.count else {
                let message = extractCannotDecomposeReason(from: raw) ?? "step is atomic"
                TelemetryEmitter.shared.emit("planner.refine.cannot_decompose", data: [
                    "reason": message
                ])
                return .cannotDecompose(reason: message)
            }

            TelemetryEmitter.shared.emit("planner.refine.success", data: [
                "substep_count": filtered.count
            ])
            return .decomposed(filtered)
        } catch {
            let message = (error as NSError).localizedDescription
            TelemetryEmitter.shared.emit("planner.refine.cannot_decompose", data: [
                "reason": message
            ])
            return .cannotDecompose(reason: message)
        }
    }

    /// Test injection point - sets the orchestration provider.
    func setOrchestrateProviderForTesting(_ provider: any LLMProvider) {
        orchestrateProvider = provider
    }

    // MARK: - Tier override parsing

    private func parseTierOverride(from message: String) -> ComplexityTier? {
        let lower = message.trimmingCharacters(in: .whitespaces).lowercased()
        if lower.hasPrefix("#high-stakes") { return .highStakes }
        if lower.hasPrefix("#standard") { return .standard }
        if lower.hasPrefix("#routine") { return .routine }
        return nil
    }

    // MARK: - Classifier call

    private func runClassifier(message: String) async -> ClassifierResult {
        let prompt = """
        Classify this user request. Respond with JSON only:
        { "needs_planning": true|false, "complexity": "routine|standard|high-stakes", "reason": "..." }

        Request: \(message)
        """

        var request = CompletionRequest(
            model: executeProvider.resolvedModelID,
            messages: [Message(role: .user, content: .text(prompt), timestamp: Date())],
            thinking: nil
        )
        let inferenceDefaults = await MainActor.run { AppSettings.shared.inferenceDefaults }
        inferenceDefaults.apply(to: &request)

        do {
            var raw = ""
            let stream = try await executeProvider.complete(request: request)
            for try await chunk in stream {
                raw += chunk.delta?.content ?? ""
            }
            return parseClassifierResult(from: raw)
        } catch {
            return ClassifierResult(needsPlanning: false, complexity: .standard, reason: "classifier unavailable")
        }
    }

    // MARK: - JSON parsing

    private func parseClassifierResult(from raw: String) -> ClassifierResult {
        let jsonString = normalizeJSONNumberLiterals(extractJSON(from: raw))
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return ClassifierResult(needsPlanning: false, complexity: .standard, reason: "parse error")
        }

        let needsPlanning = obj["needs_planning"] as? Bool ?? false
        let complexityStr = obj["complexity"] as? String ?? "standard"
        let complexity = ComplexityTier(rawValue: complexityStr) ?? .standard
        let reason = obj["reason"] as? String ?? ""

        return ClassifierResult(needsPlanning: needsPlanning, complexity: complexity, reason: reason)
    }

    nonisolated func parseStepsForTesting(from raw: String) -> [PlanStep] {
        parseSteps(from: raw)
    }

    private struct StepsEnvelope: Decodable {
        var steps: [PlanStep]
    }

    private nonisolated func parseSteps(from raw: String) -> [PlanStep] {
        let jsonString = normalizeJSONNumberLiterals(extractJSON(from: raw))
        guard let data = jsonString.data(using: .utf8) else { return [] }

        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(StepsEnvelope.self, from: data) {
            return normalizeSteps(envelope.steps)
        }
        if let bare = try? decoder.decode([PlanStep].self, from: data) {
            return normalizeSteps(bare)
        }
        if let object = try? JSONSerialization.jsonObject(with: data),
           let array = object as? [[String: Any]] {
            let decoded = array.compactMap { element -> PlanStep? in
                guard let elementData = try? JSONSerialization.data(withJSONObject: element) else {
                    return nil
                }
                return try? decoder.decode(PlanStep.self, from: elementData)
            }
            if decoded.isEmpty == false {
                return normalizeSteps(decoded)
            }
        }
        return []
    }

    private nonisolated func normalizeSteps(_ steps: [PlanStep]) -> [PlanStep] {
        steps.filter { $0.description.isEmpty == false }
    }

    private nonisolated func extractCannotDecomposeReason(from raw: String) -> String? {
        let jsonString = normalizeJSONNumberLiterals(extractJSON(from: raw))
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return obj["cannot_decompose"] as? String
            ?? obj["cannotDecompose"] as? String
            ?? obj["reason"] as? String
    }

    private nonisolated func refineReasonLabel(_ reason: RefineReason) -> String {
        switch reason {
        case .iterationCap(let loopCount, let lastObservation):
            return "iterationCap(loopCount: \(loopCount), lastObservation: \(lastObservation))"
        case .budget(let estimated, let budget):
            return "budget(estimated: \(estimated), budget: \(budget))"
        case .explicit(let text):
            return "explicit(\(text))"
        }
    }

    private nonisolated func extractJSON(from text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            let lines = s.components(separatedBy: "\n")
            if lines.count >= 2 {
                s = lines.dropFirst().dropLast().joined(separator: "\n")
            }
        }
        if s.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("["),
           let start = s.firstIndex(of: "["),
           let end = s.lastIndex(of: "]") {
            return String(s[start...end])
        }
        if let start = s.firstIndex(of: "{"), let end = s.lastIndex(of: "}") {
            return String(s[start...end])
        }
        return s
    }

    private nonisolated func normalizeJSONNumberLiterals(_ text: String) -> String {
        let characters = Array(text)
        guard characters.isEmpty == false else { return text }

        var output = String()
        output.reserveCapacity(text.count)

        for index in characters.indices {
            let character = characters[index]
            if character == "_" {
                if index != characters.startIndex {
                    let previousIndex = characters.index(before: index)
                    let nextIndex = characters.index(after: index)
                    let previousIsDigit = characters[previousIndex].isNumber
                    let nextIsDigit = nextIndex < characters.endIndex && characters[nextIndex].isNumber
                    if previousIsDigit && nextIsDigit {
                        continue
                    }
                }
            }
            output.append(character)
        }

        return output
    }
}
