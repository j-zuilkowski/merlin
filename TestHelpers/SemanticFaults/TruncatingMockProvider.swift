import Foundation
@testable import Merlin

/// LLM provider that caps all responses at `maxChars` characters.
/// Used to simulate token-boundary pressure — the model hits its max_tokens
/// limit and produces incomplete output.
///
/// Sets `finishReason` to "length" on the completion chunk so that
/// ModelParameterAdvisor can detect the maxTokensTooLow pattern.
final class TruncatingMockProvider: LLMProvider, @unchecked Sendable {
    let id: String = "truncating-mock"
    let baseURL: URL = URL(string: "http://localhost")!

    let maxChars: Int
    let baseResponse: String

    init(maxChars: Int = 20, baseResponse: String = "This is a longer response that will be cut off.") {
        self.maxChars = maxChars
        self.baseResponse = baseResponse
    }

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        let truncated = String(baseResponse.prefix(maxChars))
        let chunk = CompletionChunk(
            delta: .init(role: nil, content: truncated),
            finishReason: "length"
        )
        return AsyncThrowingStream { continuation in
            continuation.yield(chunk)
            continuation.finish()
        }
    }
}
