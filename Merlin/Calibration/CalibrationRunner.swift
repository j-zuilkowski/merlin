import Foundation

// MARK: - CalibrationRunner

/// Runs a calibration suite against local and reference providers.
///
/// The runner is closure-injected instead of coupled directly to `LLMProvider`
/// so tests can supply lightweight stubs and AppState can decide how to build
/// provider-specific requests. Both provider closures receive the full
/// `CalibrationPrompt.prompt` string; any system prompt composition happens
/// before the closure is built. The scorer is also injected and is called once
/// per response, so local and reference outputs are evaluated independently.
///
/// Results are collected concurrently and sorted by `CalibrationPrompt.id` for
/// deterministic display in the report view.
actor CalibrationRunner {

    // MARK: - Closure type aliases (also used by CalibrationAdvisor tests)

    /// Completes a single prompt against one provider and returns the raw text.
    typealias ProviderClosure = @Sendable (String) async throws -> String
    /// Scores one prompt/response pair on a 0...1 scale.
    typealias ScorerClosure = @Sendable (String, String) async throws -> Double

    // MARK: - Private

    private let localProvider: ProviderClosure
    private let referenceProvider: ProviderClosure
    private let scorer: ScorerClosure

    // MARK: - Init

    init(
        localProvider: @escaping ProviderClosure,
        referenceProvider: @escaping ProviderClosure,
        scorer: @escaping ScorerClosure
    ) {
        self.localProvider = localProvider
        self.referenceProvider = referenceProvider
        self.scorer = scorer
    }

    // MARK: - Public

    /// Fires the full battery in a TaskGroup so every prompt starts
    /// concurrently. Within each prompt, the local and reference requests also
    /// run concurrently, followed by separate scores for each response.
    func run(suite: CalibrationSuite) async throws -> [CalibrationResponse] {
        let localProvider = localProvider
        let referenceProvider = referenceProvider
        let scorer = scorer

        return try await withThrowingTaskGroup(of: CalibrationResponse.self) { group in
            for prompt in suite.prompts {
                group.addTask {
                    async let localResp = localProvider(prompt.prompt)
                    async let refResp = referenceProvider(prompt.prompt)
                    let (local, ref) = try await (localResp, refResp)

                    async let ls = scorer(prompt.prompt, local)
                    async let rs = scorer(prompt.prompt, ref)
                    let (localScore, refScore) = try await (ls, rs)

                    return CalibrationResponse(
                        prompt: prompt,
                        localResponse: local,
                        referenceResponse: ref,
                        localScore: localScore,
                        referenceScore: refScore
                    )
                }
            }

            var results: [CalibrationResponse] = []
            for try await response in group {
                results.append(response)
            }
            return results.sorted { $0.prompt.id < $1.prompt.id }
        }
    }
}
