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
            { "description": "...", "successCriteria": "...", "complexity": "routine|standard|high-stakes" }
          ]
        }

        Task: \(task)
        """

        var request = CompletionRequest(
            model: provider.id,
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
            model: executeProvider.id,
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

    private func parseSteps(from raw: String) -> [PlanStep] {
        let jsonString = extractJSON(from: raw)
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stepsArray = obj["steps"] as? [[String: Any]]
        else { return [] }

        return stepsArray.compactMap { step -> PlanStep? in
            guard let desc = step["description"] as? String else { return nil }
            let criteria = step["successCriteria"] as? String ?? ""
            let complexityStr = step["complexity"] as? String ?? "standard"
            let complexity = ComplexityTier(rawValue: complexityStr) ?? .standard
            return PlanStep(description: desc, successCriteria: criteria, complexity: complexity)
        }
    }

    private func extractJSON(from text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            let lines = s.components(separatedBy: "\n")
            if lines.count >= 2 {
                s = lines.dropFirst().dropLast().joined(separator: "\n")
            }
        }
        if let start = s.firstIndex(of: "{"), let end = s.lastIndex(of: "}") {
            return String(s[start...end])
        }
        return s
    }
}
