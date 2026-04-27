import Foundation

final class LMStudioProvider: LLMProvider, @unchecked Sendable {
    let model: String

    var id: String { model }
    var baseURL: URL { URL(string: "http://localhost:1234/v1")! }

    init(model: String = "Qwen2.5-VL-72B-Instruct-Q4_K_M") {
        self.model = model
    }

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        let endpoint = baseURL.appendingPathComponent("chat/completions").absoluteString
        let requestBody = try buildRequestBody(request)

        return AsyncThrowingStream { continuation in
            let task = Task { @Sendable in
                do {
                    var urlRequest = URLRequest(url: URL(string: endpoint)!)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.httpBody = requestBody

                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        throw URLError(.badServerResponse)
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
        try encodeRequest(request, baseURL: baseURL, model: model, includeThinking: false)
    }
}
