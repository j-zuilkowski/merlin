import Foundation

final class DeepSeekProvider: LLMProvider, @unchecked Sendable {
    let apiKey: String
    let model: String

    var id: String { model }
    var baseURL: URL { URL(string: "https://api.deepseek.com/v1")! }

    init(apiKey: String, model: String = "deepseek-v4-pro") {
        self.apiKey = apiKey
        self.model = model
    }

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        let endpoint = baseURL.appendingPathComponent("chat/completions").absoluteString
        let requestBody = try buildRequestBody(request)
        let token = apiKey

        return AsyncThrowingStream { continuation in
            let task = Task { @Sendable in
                do {
                    var urlRequest = URLRequest(url: URL(string: endpoint)!)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.timeoutInterval = 600 // match OpenAICompatibleProvider
                    urlRequest.httpBody = requestBody

                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        // Collect the error body so we can surface a useful message.
                        var errorLines: [String] = []
                        for try await line in bytes.lines { errorLines.append(line) }
                        let body = errorLines.joined(separator: "\n").prefix(500)
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                        throw URLError(.badServerResponse,
                            userInfo: [NSLocalizedDescriptionKey: "DeepSeek HTTP \(statusCode): \(body)"])
                    }

                    for try await line in bytes.lines {
                        if let chunk = try SSEParser.parseChunk(line) {
                            continuation.yield(chunk)
                        }
                        if line.trimmingCharacters(in: .whitespacesAndNewlines) == "data: [DONE]" {
                            break
                        }
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

    func buildRequestBody(_ request: CompletionRequest) throws -> Data {
        try encodeRequest(request, baseURL: baseURL, model: model)
    }
}
