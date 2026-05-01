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
        // Large-context requests (e.g. 100 K+ tokens) can take 90–120 s before the
        // first streaming token arrives. URLRequest's default 60-second timeout fires
        // before the response starts. Set a long ceiling so the connection stays open;
        // the user can always hit Stop for a manual cancel.
        urlRequest.timeoutInterval = 600 // 10 minutes
        urlRequest.httpBody = try encodeRequest(request, baseURL: baseURL, model: modelID)
        return urlRequest
    }

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        let urlRequest = try buildRequest(request)
        return AsyncThrowingStream { continuation in
            let task = Task { @Sendable in
                // Retry once on connection-level failures (NSURLErrorBadServerResponse / -1011).
                // DeepSeek and other OpenAI-compatible APIs occasionally drop the connection
                // without sending a valid HTTP response — a single retry resolves these.
                var attempt = 0
                while attempt < 2 {
                    attempt += 1
                    do {
                        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                            var errorLines: [String] = []
                            for try await line in bytes.lines { errorLines.append(line) }
                            let body = errorLines.joined(separator: "\n").prefix(500)
                            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                            // 4xx errors are definitive — don't retry.
                            throw URLError(.badServerResponse,
                                userInfo: [NSLocalizedDescriptionKey: "HTTP \(statusCode): \(body)"])
                        }

                        for try await line in bytes.lines {
                            if let chunk = try SSEParser.parseChunk(line) {
                                continuation.yield(chunk)
                                if chunk.finishReason != nil {
                                    break
                                }
                            }
                        }
                        continuation.finish()
                        return
                    } catch let urlError as URLError
                        where urlError.code == .badServerResponse && attempt < 2 {
                        // -1011: connection dropped before HTTP response — wait briefly and retry.
                        try? await Task.sleep(for: .seconds(2))
                        continue
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}
