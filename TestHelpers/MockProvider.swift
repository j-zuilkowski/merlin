import Foundation
@testable import Merlin

final class MockProvider: LLMProvider, @unchecked Sendable {
    var id_: String = "mock"
    var id: String { id_ }
    var baseURL: URL { URL(string: "http://localhost")! }
    var wasUsed = false
    private let chunks: [CompletionChunk]
    private var responses: [MockLLMResponse]
    private var responseIndex = 0

    init(chunks: [CompletionChunk]) { self.chunks = chunks; self.responses = [] }
    init(responses: [MockLLMResponse]) { self.chunks = []; self.responses = responses }

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        wasUsed = true
        let toSend: [CompletionChunk]
        if !responses.isEmpty {
            let resp = responses[min(responseIndex, responses.count - 1)]
            responseIndex += 1
            toSend = resp.chunks
        } else {
            toSend = chunks
        }
        return AsyncThrowingStream { continuation in
            for chunk in toSend { continuation.yield(chunk) }
            continuation.finish()
        }
    }
}

enum MockLLMResponse {
    case text(String)
    case toolCall(id: String, name: String, args: String)

    var chunks: [CompletionChunk] {
        switch self {
        case .text(let s):
            return [
                CompletionChunk(delta: .init(content: s), finishReason: nil),
                CompletionChunk(delta: nil, finishReason: "stop"),
            ]
        case .toolCall(let id, let name, let args):
            return [
                CompletionChunk(delta: .init(toolCalls: [
                    .init(index: 0, id: id, function: .init(name: name, arguments: args))
                ]), finishReason: nil),
                CompletionChunk(delta: nil, finishReason: "tool_calls"),
            ]
        }
    }
}
