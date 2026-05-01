import Foundation

final class OpenAICompatibleProvider: LLMProvider, @unchecked Sendable {

    let id: String
    let baseURL: URL
    private let apiKey: String?
    private let modelID: String
    /// Injectable URLSession - defaults to shared; overridden in tests via mock protocol.
    private let session: URLSession

    init(id: String, baseURL: URL, apiKey: String?, modelID: String,
         session: URLSession = .shared) {
        self.id = id
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelID = modelID
        self.session = session
    }

    private func buildRequestAndEncodeMs(_ request: CompletionRequest) throws -> (URLRequest, Double) {
        let encodeStart = Date()
        let url = baseURL.appendingPathComponent("chat/completions")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = apiKey, !key.isEmpty {
            urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        urlRequest.timeoutInterval = 600
        urlRequest.httpBody = try encodeRequest(request, baseURL: baseURL, model: modelID)
        let encodeMs = Date().timeIntervalSince(encodeStart) * 1000
        return (urlRequest, encodeMs)
    }

    func buildRequest(_ request: CompletionRequest) throws -> URLRequest {
        try buildRequestAndEncodeMs(request).0
    }

    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        let (urlRequest, encodeMs) = try buildRequestAndEncodeMs(request)
        let bodyBytes = urlRequest.httpBody?.count ?? 0
        let providerID = id

        TelemetryEmitter.shared.emit("request.encode", data: [
            "provider": providerID,
            "body_bytes": bodyBytes,
            "encode_duration_ms": encodeMs,
            "message_count": request.messages.count,
            "tool_count": request.tools?.count ?? 0
        ])
        TelemetryEmitter.shared.emit("request.sent", data: [
            "provider": providerID,
            "url": urlRequest.url?.absoluteString ?? "",
            "body_bytes": bodyBytes,
            "message_count": request.messages.count,
            "tool_count": request.tools?.count ?? 0,
            "model": request.model
        ])

        let requestStart = Date()

        return AsyncThrowingStream { continuation in
            let task = Task { @Sendable [session] in
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
                        let (bytes, response) = try await session.bytes(for: urlRequest)
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
                                userInfo: [NSLocalizedDescriptionKey: "HTTP \(statusCode): \(body)"])
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
                                if chunk.finishReason != nil { break }
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
}
