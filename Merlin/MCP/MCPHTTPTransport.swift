@preconcurrency import Foundation

enum MCPTransportKind: String, Codable, Sendable {
    case stdio
    case http
    case sse
}

enum MCPTransportError: Error, Sendable, Equatable {
    case httpStatus(Int, String)
    case decodeError(String)
    case transportClosed
    case invalidResponse(String)
    case mismatchedResponseID(expected: Int, actual: Int?)
}

protocol MCPTransportSession: Sendable {
    func launch() async throws
    func call(method: String, params: [String: Any]) async throws -> [String: Any]
    func terminate() async
}

extension MCPTransportSession {
    func listTools() async throws -> [MCPToolDefinition] {
        let response = try await call(method: "tools/list", params: [:])
        guard let toolsArray = response["tools"] as? [[String: Any]] else {
            return []
        }
        let data = try JSONSerialization.data(withJSONObject: toolsArray)
        return (try? JSONDecoder().decode([MCPToolDefinition].self, from: data)) ?? []
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> String {
        let response = try await call(method: "tools/call", params: [
            "name": name,
            "arguments": arguments
        ])
        if let content = response["content"] as? [[String: Any]],
           let first = content.first,
           let text = first["text"] as? String {
            return text
        }
        return String(data: (try? JSONSerialization.data(withJSONObject: response)) ?? Data(),
                      encoding: .utf8) ?? ""
    }
}

final class MCPHTTPTransport: MCPTransportSession, @unchecked Sendable {
    let endpoint: URL
    private let session: URLSession
    private let lock = NSLock()
    private var nextID: Int = 1

    init(endpoint: URL, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
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
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = requestData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MCPTransportError.invalidResponse("Expected HTTPURLResponse")
        }

        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw MCPTransportError.httpStatus(http.statusCode, body)
        }

        let raw = try JSONSerialization.jsonObject(with: data)
        guard let object = raw as? [String: Any] else {
            throw MCPTransportError.decodeError("Expected top-level JSON object")
        }

        let responseID = Self.extractIntID(from: object["id"])
        guard responseID == requestID else {
            throw MCPTransportError.mismatchedResponseID(expected: requestID, actual: responseID)
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
