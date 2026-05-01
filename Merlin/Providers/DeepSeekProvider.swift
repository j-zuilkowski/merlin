import Foundation

final class DeepSeekProvider: LLMProvider, @unchecked Sendable {
    let apiKey: String
    let model: String

    var id: String  { model }
    var baseURL: URL { URL(string: "https://api.deepseek.com/v1")! }

    init(apiKey: String, model: String = "deepseek-v4-pro") {
        self.apiKey = apiKey
        self.model  = model
    }

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        let endpoint = baseURL.appendingPathComponent("chat/completions").absoluteString
        let encodeStart = Date()
        let requestBody = try buildRequestBody(request)
        let encodeMs = Date().timeIntervalSince(encodeStart) * 1000
        let token = apiKey
        let providerID = id

        TelemetryEmitter.shared.emit("request.encode", data: [
            "provider": providerID,
            "body_bytes": requestBody.count,
            "encode_duration_ms": encodeMs,
            "message_count": request.messages.count,
            "tool_count": request.tools?.count ?? 0
        ])
        TelemetryEmitter.shared.emit("request.sent", data: [
            "provider": providerID,
            "url": endpoint,
            "body_bytes": requestBody.count,
            "message_count": request.messages.count,
            "tool_count": request.tools?.count ?? 0,
            "model": request.model
        ])

        let requestStart = Date()

        return AsyncThrowingStream { continuation in
            let task = Task { @Sendable in
                var attempt = 0
                while attempt < 2 {
                    attempt += 1
                    if attempt > 1 {
                        TelemetryEmitter.shared.emit("request.retry", data: [
                            "provider": providerID,
                            "attempt": attempt
                        ])
                        try? await Task.sleep(for: .seconds(2))
                    }
                    do {
                        var urlRequest = URLRequest(url: URL(string: endpoint)!)
                        urlRequest.httpMethod = "POST"
                        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        urlRequest.timeoutInterval = 600
                        urlRequest.httpBody = requestBody

                        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                        guard let http = response as? HTTPURLResponse,
                              (200...299).contains(http.statusCode) else {
                            var errorLines: [String] = []
                            for try await line in bytes.lines { errorLines.append(line) }
                            let body = errorLines.joined(separator: "\n").prefix(500)
                            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                            TelemetryEmitter.shared.emit("request.error", data: [
                                "provider": providerID,
                                "error_code": statusCode,
                                "error_detail": String(body)
                            ])
                            throw URLError(.badServerResponse,
                                userInfo: [NSLocalizedDescriptionKey: "DeepSeek HTTP \(statusCode): \(body)"])
                        }

                        var firstToken = true
                        for try await line in bytes.lines {
                            if let chunk = try SSEParser.parseChunk(line) {
                                if firstToken {
                                    firstToken = false
                                    let ttft = Date().timeIntervalSince(requestStart) * 1000
                                    TelemetryEmitter.shared.emit("request.ttft", data: [
                                        "provider": providerID,
                                        "ttft_ms": ttft
                                    ])
                                }
                                continuation.yield(chunk)
                            }
                            if line.trimmingCharacters(in: .whitespacesAndNewlines) == "data: [DONE]" {
                                break
                            }
                        }
                        let totalMs = Date().timeIntervalSince(requestStart) * 1000
                        TelemetryEmitter.shared.emit("request.complete", durationMs: totalMs, data: [
                            "provider": providerID,
                            "model": request.model
                        ])
                        continuation.finish()
                        return
                    } catch let urlError as URLError
                        where urlError.code == .badServerResponse && attempt < 2 {
                        continue
                    } catch {
                        TelemetryEmitter.shared.emit("request.error", data: [
                            "provider": providerID,
                            "error_domain": (error as NSError).domain,
                            "error_code": (error as NSError).code
                        ])
                        continuation.finish(throwing: error)
                        return
                    }
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    func buildRequestBody(_ request: CompletionRequest) throws -> Data {
        try encodeRequest(request, baseURL: baseURL, model: model)
    }
}
