@preconcurrency import Foundation

struct MCPSSEFrameParser {
    private var currentDataLines: [String] = []

    mutating func ingest(_ chunk: String) -> [String] {
        var frames: [String] = []
        for rawLine in chunk.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.isEmpty {
                flush(into: &frames)
                continue
            }
            if line.hasPrefix(":") {
                continue
            }
            guard line.hasPrefix("data:") else {
                continue
            }
            let data = line.dropFirst(5)
            let trimmed = data.hasPrefix(" ") ? data.dropFirst() : data[...]
            currentDataLines.append(String(trimmed))
        }
        return frames
    }

    mutating func finish() -> [String] {
        var frames: [String] = []
        flush(into: &frames)
        return frames
    }

    private mutating func flush(into frames: inout [String]) {
        guard !currentDataLines.isEmpty else { return }
        frames.append(currentDataLines.joined(separator: "\n"))
        currentDataLines.removeAll(keepingCapacity: true)
    }
}

final class MCPSSETransport: MCPTransportSession, @unchecked Sendable {
    let endpoint: URL
    private let session: URLSession?
    private let injectedStream: AsyncThrowingStream<String, Error>?
    private let lock = NSLock()
    private var nextID: Int = 1

    init(endpoint: URL, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
        self.injectedStream = nil
    }

    init(endpoint: URL, eventStream: AsyncThrowingStream<String, Error>) {
        self.endpoint = endpoint
        self.session = nil
        self.injectedStream = eventStream
    }

    func launch() async throws {}

    func terminate() async {}

    func call(method: String, params: [String: Any]) async throws -> [String: Any] {
        let requestID = nextRequestID()
        let requestBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestID,
            "method": method,
            "params": params
        ]

        let requestData = try JSONSerialization.data(withJSONObject: requestBody, options: [])

        if let stream = injectedStream {
            _ = requestData
            return try await readResponse(from: stream, requestID: requestID)
        }

        guard let session else {
            throw MCPTransportError.transportClosed
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = requestData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MCPTransportError.invalidResponse("Expected HTTPURLResponse")
        }
        guard (200...299).contains(http.statusCode) else {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            throw MCPTransportError.httpStatus(http.statusCode, body)
        }

        return try await readResponse(from: bytes.lines, requestID: requestID)
    }

    private func readResponse<Lines: AsyncSequence>(
        from lines: Lines,
        requestID: Int
    ) async throws -> [String: Any] where Lines.Element == String {
        var parser = MCPSSEFrameParser()
        for try await line in lines {
            let payloads = parser.ingest(line + "\n")
            for payload in payloads {
                if payload == "[DONE]" {
                    throw MCPTransportError.transportClosed
                }
                if let result = try decodeResponse(payload: payload, requestID: requestID) {
                    return result
                }
            }
        }

        let trailing = parser.finish()
        for payload in trailing {
            if let result = try decodeResponse(payload: payload, requestID: requestID) {
                return result
            }
        }

        throw MCPTransportError.transportClosed
    }

    private func decodeResponse(payload: String, requestID: Int) throws -> [String: Any]? {
        guard let data = payload.data(using: .utf8) else {
            throw MCPTransportError.decodeError("Invalid UTF-8 SSE payload")
        }

        let raw = try JSONSerialization.jsonObject(with: data)
        guard let object = raw as? [String: Any] else {
            throw MCPTransportError.decodeError("Expected JSON object in SSE frame")
        }

        let responseID = Self.extractIntID(from: object["id"])
        guard responseID == requestID else {
            return nil
        }

        if let result = object["result"] as? [String: Any] {
            return result
        }
        if let error = object["error"] as? [String: Any] {
            let message = (error["message"] as? String) ?? "MCP error"
            throw MCPTransportError.invalidResponse(message)
        }
        throw MCPTransportError.decodeError("Missing JSON-RPC result")
    }

    private func nextRequestID() -> Int {
        lock.withLock {
            defer { nextID += 1 }
            return nextID
        }
    }

    private static func extractIntID(from value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }
}
