import Foundation

// MARK: - CalibrationRunner

/// Runs a CalibrationSuite against two providers in parallel and scores each response.
///
/// `localProvider` and `referenceProvider` are `(prompt: String) async throws -> String`
/// closures — the caller (AppState) builds them from real LLMProvider instances.
/// `scorer` is a `(prompt: String, response: String) async throws -> Double` closure
/// that returns a quality score in [0, 1]; in production this wraps CriticEngine.
///
/// Results are sorted by `CalibrationPrompt.id` for deterministic UI display.
actor CalibrationRunner {

    // MARK: - Closure type aliases (also used by CalibrationAdvisor tests)

    typealias ProviderClosure = @Sendable (String) async throws -> String
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

    /// Fires all prompts in `suite` in parallel - local and reference calls for each
    /// prompt run concurrently. Returns one `CalibrationResponse` per prompt, sorted
    /// by prompt ID.
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
