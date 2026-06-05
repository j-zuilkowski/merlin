import Foundation
@testable import Merlin

final class MockProvider: LLMProvider, @unchecked Sendable {
    var id_: String = "mock"
    var id: String { id_ }
    var baseURL: URL { URL(string: "http://localhost")! }
    var wasUsed = false
    var stubbedResponse: String?
    var stubbedChunks: [String] = []
    private let chunks: [CompletionChunk]
    private var responses: [MockLLMResponse]
    private var responseIndex = 0
    private let delay: TimeInterval

    /// Optional error sequence consumed in order by `complete`. A `nil` entry means
    /// "succeed normally". Entries beyond the array length always succeed normally.
    var stubbedErrors: [Error?] = []
    private var errorIndex = 0
    private(set) var callCount: Int = 0
    private(set) var requests: [CompletionRequest] = []
    private let firstCallError: ProviderError?
    private let allCallsError: ProviderError?

    init() {
        self.chunks = []
        self.responses = []
        self.delay = 0
        self.firstCallError = nil
        self.allCallsError = nil
    }

    init(response: String = "mock response",
         delay: TimeInterval = 0,
         shouldFail: Bool = false,
         failFirstCallWith firstError: ProviderError? = nil,
         failAllCallsWith allError: ProviderError? = nil) {
        self.chunks = []
        self.responses = []
        self.delay = delay
        self.stubbedResponse = response
        self.firstCallError = firstError
        let genericError: ProviderError? = shouldFail
            ? .httpError(statusCode: 400, body: "mock failure", providerID: "mock")
            : nil
        self.allCallsError = allError ?? genericError
    }

    init(chunks: [CompletionChunk]) {
        self.chunks = chunks
        self.responses = []
        self.delay = 0
        self.firstCallError = nil
        self.allCallsError = nil
    }

    init(responses: [MockLLMResponse]) {
        self.chunks = []
        self.responses = responses
        self.delay = 0
        self.firstCallError = nil
        self.allCallsError = nil
    }

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        callCount += 1
        requests.append(request)
        if let error = allCallsError { throw error }
        if callCount == 1, let error = firstCallError { throw error }
        if errorIndex < stubbedErrors.count {
            let maybeError = stubbedErrors[errorIndex]
            errorIndex += 1
            if let error = maybeError { throw error }
        }
        if delay > 0 {
            try await Task.sleep(for: .seconds(delay))
        }
        wasUsed = true
        let toSend: [CompletionChunk]
        if let stubbedResponse {
            toSend = [
                CompletionChunk(delta: .init(content: stubbedResponse), finishReason: nil),
                CompletionChunk(delta: nil, finishReason: "stop"),
            ]
        } else if stubbedChunks.isEmpty == false {
            toSend = stubbedChunks.map { CompletionChunk(delta: .init(content: $0), finishReason: nil) } + [
                CompletionChunk(delta: nil, finishReason: "stop"),
            ]
        } else if !responses.isEmpty {
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
