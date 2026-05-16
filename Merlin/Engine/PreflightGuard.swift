import Foundation

/// Last-line guard so no `provider.complete` call sends an over-budget request.
/// The main turn loop has the richer `AgenticEngine.preflightCheck` (which compacts
/// the live ContextManager); this guard is the universal floor for every other path.
enum PreflightGuard {

    /// Returns a request whose `TokenEstimator.estimate` is <= `usableInputTokens`
    /// whenever it is possible to do so by dropping old non-system messages and
    /// truncating the largest remaining text message.
    static func fit(_ request: CompletionRequest,
                    usableInputTokens: Int) -> CompletionRequest {
        let budget = max(1, usableInputTokens)
        let beforeEstimate = TokenEstimator.estimate(request: request)
        guard beforeEstimate > budget, request.messages.isEmpty == false else {
            return request
        }

        var fitted = request
        while TokenEstimator.estimate(request: fitted) > budget,
              countNonSystemMessages(in: fitted) > 1,
              let dropIndex = fitted.messages.firstIndex(where: { $0.role != .system }) {
            fitted.messages.remove(at: dropIndex)
        }

        while TokenEstimator.estimate(request: fitted) > budget {
            guard let index = largestTextMessageIndex(in: fitted),
                  let replacement = truncatedTextFittingBudget(
                    request: fitted,
                    messageIndex: index,
                    usableInputTokens: budget
                  )
            else {
                break
            }

            let current = fitted.messages[index].content.plainText
            guard replacement.count < current.count else {
                break
            }
            fitted.messages[index].content = .text(replacement)
        }

        let afterEstimate = TokenEstimator.estimate(request: fitted)
        if afterEstimate < beforeEstimate {
            TelemetryEmitter.shared.emit("engine.preflight.guard_clamped", data: [
                "before_estimate": beforeEstimate,
                "after_estimate": afterEstimate,
                "usable_input_tokens": budget
            ])
        }
        return fitted
    }

    /// Clamp-to-fit then send. A drop-in replacement for `provider.complete(request:)`.
    static func complete(_ request: CompletionRequest,
                         provider: any LLMProvider)
        async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        let budget = await ContextBudgetResolver.shared.usableInputTokens(for: provider)
        let fitted = fit(request, usableInputTokens: budget)

        do {
            let stream = try await provider.complete(request: fitted)
            return streamWithOverflowRetry(stream, originalRequest: request, provider: provider)
        } catch let error as ProviderError where error.isContextLengthExceeded {
            return try await retryAfterOverflow(error: error, request: request, provider: provider)
        }
    }

    private static func countNonSystemMessages(in request: CompletionRequest) -> Int {
        request.messages.reduce(0) { count, message in
            count + (message.role == .system ? 0 : 1)
        }
    }

    private static func largestTextMessageIndex(in request: CompletionRequest) -> Int? {
        request.messages.indices
            .filter { request.messages[$0].content.plainText.isEmpty == false }
            .max { lhs, rhs in
                request.messages[lhs].content.plainText.count < request.messages[rhs].content.plainText.count
            }
    }

    private static func truncatedTextFittingBudget(
        request: CompletionRequest,
        messageIndex: Int,
        usableInputTokens: Int
    ) -> String? {
        let text = request.messages[messageIndex].content.plainText
        guard text.isEmpty == false else { return nil }

        var low = 1
        var high = text.count - 1
        var best: String?

        while low <= high {
            let mid = (low + high) / 2
            let candidate = ToolOutput.clamp(text, maxChars: mid)
            var trial = request
            trial.messages[messageIndex].content = .text(candidate)

            if TokenEstimator.estimate(request: trial) <= usableInputTokens {
                best = candidate
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return best ?? ToolOutput.clamp(text, maxChars: 1)
    }

    private static func streamWithOverflowRetry(
        _ stream: AsyncThrowingStream<CompletionChunk, Error>,
        originalRequest: CompletionRequest,
        provider: any LLMProvider
    ) -> AsyncThrowingStream<CompletionChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @Sendable in
                var yieldedChunk = false
                do {
                    for try await chunk in stream {
                        yieldedChunk = true
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch let error as ProviderError where error.isContextLengthExceeded && yieldedChunk == false {
                    do {
                        let retryStream = try await retryAfterOverflow(
                            error: error,
                            request: originalRequest,
                            provider: provider
                        )
                        for try await chunk in retryStream {
                            continuation.yield(chunk)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func retryAfterOverflow(
        error: ProviderError,
        request: CompletionRequest,
        provider: any LLMProvider
    ) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        if let learned = error.observedContextLimit {
            await ContextBudgetResolver.shared.recordObservedLimit(
                contextTokens: learned,
                for: provider
            )
        }
        let corrected = await ContextBudgetResolver.shared.usableInputTokens(for: provider)
        return try await provider.complete(request: fit(request, usableInputTokens: corrected))
    }
}
