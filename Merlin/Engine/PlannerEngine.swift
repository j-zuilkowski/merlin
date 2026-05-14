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

// MARK: - PlanStep

struct PlanStep: Sendable {
    var description: String
    var successCriteria: String
    var complexity: ComplexityTier
    var parallelSafe: Bool = false
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

        let prompt = """
        Decompose the following task into concrete implementation steps.
        Respond with JSON only - no prose before or after:
        {
          "steps": [
            {
              "step": "...",
              "success_criteria": "...",
              "complexity": "routine|standard|high_stakes",
              "parallel_safe": true
            }
          ]
        }

        Each step must be a JSON object with keys:
          "step"             — concise imperative description
          "success_criteria" — how to verify the step is done
          "complexity"       — "routine", "standard", or "high_stakes"
          "parallel_safe"    — true if this step has no dependency on sibling output and
                               touches different files; false otherwise (default false when unsure)

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
        let jsonString = extractJSON(from: raw)
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

    private struct RawStep: Decodable {
        var step: String?
        var description: String?
        var success_criteria: String?
        var successCriteria: String?
        var complexity: String?
        var parallel_safe: Bool?
    }

    private struct RawStepsEnvelope: Decodable {
        var steps: [RawStep]
    }

    private nonisolated func parseSteps(from raw: String) -> [PlanStep] {
        let jsonString = extractJSON(from: raw)
        guard let data = jsonString.data(using: .utf8) else { return [] }

        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(RawStepsEnvelope.self, from: data) {
            return envelope.steps.compactMap(planStep(from:))
        }
        if let bare = try? decoder.decode([RawStep].self, from: data) {
            return bare.compactMap(planStep(from:))
        }
        return []
    }

    private nonisolated func planStep(from raw: RawStep) -> PlanStep? {
        guard let desc = raw.step ?? raw.description else { return nil }
        return PlanStep(
            description: desc,
            successCriteria: raw.success_criteria ?? raw.successCriteria ?? "",
            complexity: tier(from: raw.complexity),
            parallelSafe: raw.parallel_safe ?? false
        )
    }

    private nonisolated func tier(from raw: String?) -> ComplexityTier {
        switch raw?.lowercased() {
        case "routine":
            return .routine
        case "high_stakes", "high-stakes":
            return .highStakes
        default:
            return .standard
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
}
