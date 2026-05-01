import Foundation

// Single wrapper covering all OpenAI-compatible endpoints.
final class OpenAICompatibleProvider: LLMProvider, @unchecked Sendable {

    let id: String
    let baseURL: URL
    private let apiKey: String?
    private let modelID: String

    init(id: String, baseURL: URL, apiKey: String?, modelID: String) {
        self.id = id
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelID = modelID
    }

    func buildRequest(_ request: CompletionRequest) throws -> URLRequest {
        let url = baseURL.appendingPathComponent("chat/completions")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = apiKey, !key.isEmpty {
            urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.httpBody = try encodeRequest(request, baseURL: baseURL, model: modelID)
        return urlRequest
    }

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        let urlRequest = try buildRequest(request)
        return AsyncThrowingStream { continuation in
            let task = Task { @Sendable in
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        var errorLines: [String] = []
                        for try await line in bytes.lines { errorLines.append(line) }
                        let body = errorLines.joined(separator: "\n").prefix(500)
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                        throw URLError(.badServerResponse,
                            userInfo: [NSLocalizedDescriptionKey: "HTTP \(statusCode): \(body)"])
                    }

                    // Stream with idle timeout: if no SSE chunk arrives for 45 s the
                    // connection has stalled. Cancel the task so the engine can surface
                    // a clear error rather than hanging indefinitely.
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask { @Sendable in
                            for try await line in bytes.lines {
                                if let chunk = try SSEParser.parseChunk(line) {
                                    continuation.yield(chunk)
                                    if chunk.finishReason != nil { return }
                                }
                            }
                        }
                        group.addTask { @Sendable in
                            try await Task.sleep(nanoseconds: 45_000_000_000)
                            throw URLError(.timedOut, userInfo: [
                                NSLocalizedDescriptionKey:
                                    "Stream stalled — no response from the API for 45 seconds. " +
                                    "The request may be too large. Try a shorter prompt or a new session."
                            ])
                        }
                        // First task to finish (stream end or timeout error) wins.
                        try await group.next()
                        group.cancelAll()
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}
