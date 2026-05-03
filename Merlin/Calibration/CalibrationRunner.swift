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
/// Prompts run sequentially so local inference backends (e.g. LM Studio) are
/// never flooded with concurrent requests they must serialise internally. Within
/// each prompt, the local and reference requests run concurrently because they
/// target different backends. An optional `onProgress` callback receives the
/// completed count after each prompt so callers can update progress UI.
actor CalibrationRunner {

    // MARK: - Closure type aliases (also used by CalibrationAdvisor tests)

    /// Completes a single prompt against one provider and returns the raw text.
    typealias ProviderClosure = @Sendable (String) async throws -> String
    /// Scores one prompt/response pair on a 0...1 scale.
    typealias ScorerClosure = @Sendable (String, String) async throws -> Double
    /// Called on MainActor after each prompt completes with the running total.
    typealias ProgressClosure = @MainActor @Sendable (Int) -> Void

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

    /// Runs every prompt sequentially to avoid saturating single-threaded local
    /// inference backends. Within each prompt, local and reference requests run
    /// concurrently (different backends). `onProgress` is called on MainActor
    /// after each prompt so the UI can display live counts.
    func run(
        suite: CalibrationSuite,
        onProgress: ProgressClosure? = nil
    ) async throws -> [CalibrationResponse] {
        let localProvider = localProvider
        let referenceProvider = referenceProvider
        let scorer = scorer

        var results: [CalibrationResponse] = []

        for (index, prompt) in suite.prompts.enumerated() {
            // Local and reference can run concurrently — they target different backends.
            async let localResp = localProvider(prompt.prompt)
            async let refResp = referenceProvider(prompt.prompt)
            let (local, ref) = try await (localResp, refResp)

            // Scorer uses the reason-slot provider (also local); run sequentially
            // to avoid queuing two requests on the same LM Studio instance.
            let localScore = try await scorer(prompt.prompt, local)
            let refScore   = try await scorer(prompt.prompt, ref)

            results.append(CalibrationResponse(
                prompt: prompt,
                localResponse: local,
                referenceResponse: ref,
                localScore: localScore,
                referenceScore: refScore
            ))

            let completed = index + 1
            if let onProgress {
                await onProgress(completed)
            }
        }

        return results.sorted { $0.prompt.id < $1.prompt.id }
    }
}
