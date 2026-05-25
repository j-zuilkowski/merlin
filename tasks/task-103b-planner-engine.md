# Phase 103b — PlannerEngine (classifier + decomposer + complexity routing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 103a complete: failing PlannerEngine tests in place.

---

## Write to: Merlin/Engine/PlannerEngine.swift

```swift
import Foundation

// MARK: - ComplexityTier

/// Domain-agnostic task complexity tiers.
/// Examples vary by active domain (software, PCB, construction).
enum ComplexityTier: String, Codable, Equatable, Sendable {
    case routine      // local execute only; skip critic
    case standard     // local execute + reason critic
    case highStakes = "high-stakes"   // reason slot execute + reason critic
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
///   3. Critic evaluates the plan before execution begins
///   4. Tier overrides (`#high-stakes`, `#routine`, `#standard`) bypass classifier
actor PlannerEngine {

    private let executeProvider: any LLMProvider
    private let orchestrateProvider: (any LLMProvider)?
    private let maxPlanRetries: Int

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

    /// Classifies the task. Tier override annotations (`#high-stakes` etc.) take precedence
    /// over the classifier's output.
    func classify(message: String, domain: any DomainPlugin) async -> ClassifierResult {
        // 1. Check declarative tier override
        if let override = parseTierOverride(from: message) {
            return ClassifierResult(
                needsPlanning: override != .routine,
                complexity: override,
                reason: "declarative override"
            )
        }

        // 2. Check domain high-stakes keywords
        let lower = message.lowercased()
        for keyword in domain.highStakesKeywords {
            if lower.contains(keyword.lowercased()) {
                return ClassifierResult(
                    needsPlanning: true,
                    complexity: .highStakes,
                    reason: "high-stakes keyword: \(keyword)"
                )
            }
        }

        // 3. Call execute-slot classifier for JSON result
        return await runClassifier(message: message)
    }

    // MARK: - Decomposition

    /// Decomposes the task into steps using the orchestrate slot.
    /// Returns [] on any failure — caller falls back to direct execution.
    func decompose(task: String, context: [Message]) async -> [PlanStep] {
        guard let provider = orchestrateProvider else { return [] }

        let prompt = """
        Decompose the following task into concrete implementation steps.
        Respond with JSON only — no prose before or after:
        {
          "steps": [
            { "description": "...", "successCriteria": "...", "complexity": "routine|standard|high-stakes" }
          ]
        }

        Task: \(task)
        """

        let request = CompletionRequest(
            model: provider.id,
            messages: [Message(role: .user, content: .text(prompt), timestamp: Date())],
            thinking: nil
        )

        do {
            var raw = ""
            let stream = try await provider.complete(request: request)
            for try await chunk in stream { raw += chunk.delta?.content ?? "" }
            return parseSteps(from: raw)
        } catch {
            return []
        }
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

        let request = CompletionRequest(
            model: executeProvider.id,
            messages: [Message(role: .user, content: .text(prompt), timestamp: Date())],
            thinking: nil
        )

        do {
            var raw = ""
            let stream = try await executeProvider.complete(request: request)
            for try await chunk in stream { raw += chunk.delta?.content ?? "" }
            return parseClassifierResult(from: raw)
        } catch {
            return ClassifierResult(needsPlanning: false, complexity: .standard, reason: "classifier unavailable")
        }
    }

    // MARK: - JSON parsing

    private func parseClassifierResult(from raw: String) -> ClassifierResult {
        // Extract JSON from potential prose wrapping
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
        // Strip markdown code fences if present
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            let lines = s.components(separatedBy: "\n")
            s = lines.dropFirst().dropLast().joined(separator: "\n")
        }
        // Find first { to last }
        if let start = s.firstIndex(of: "{"), let end = s.lastIndex(of: "}") {
            return String(s[start...end])
        }
        return s
    }
}
```

---

## AppSettings additions (add to Merlin/Config/AppSettings.swift)

```swift
// MARK: - V5 Planner

@Published var maxPlanRetries: Int = 2
@Published var maxLoopIterations: Int = 10
```

Load in `load(from:)` under `[planner]` TOML key:
```swift
if let planner = toml["planner"] as? [String: Any] {
    maxPlanRetries    = planner["max_plan_retries"]    as? Int ?? 2
    maxLoopIterations = planner["max_loop_iterations"] as? Int ?? 10
}
```

config.toml schema:
```toml
[planner]
max_plan_retries    = 2    # plan revision loops before escalating to user
max_loop_iterations = 10   # hard ceiling on step-execution loop
```

---

## project.yml additions

Add:
```yaml
- Merlin/Engine/PlannerEngine.swift
```

Then:
```bash
cd ~/Documents/localProject/merlin
xcodegen generate
```

---

## Verify
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'PlannerEngine.*passed|PlannerEngine.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED; PlannerEngineTests → 7 pass; zero warnings.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/PlannerEngine.swift \
        Merlin/Config/AppSettings.swift \
        project.yml
git commit -m "Phase 103b — PlannerEngine (execute-slot classifier + orchestrate decomposer + complexity routing)"
```
