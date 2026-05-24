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

    func callTool(name: String, argumentsJSON: String) async throws -> String {
        let arguments = Self.decodeArguments(from: argumentsJSON)
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

    func readResourceText(uri: String) async throws -> String? {
        let response = try await call(method: "resources/read", params: ["uri": uri])
        return Self.extractResourceText(from: response)
    }

    private static func decodeArguments(from json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return [:]
        }
        return dictionary
    }

    private static func extractResourceText(from response: [String: Any]) -> String? {
        if let text = response["text"] as? String, !text.isEmpty {
            return text
        }
        guard let contents = response["contents"] as? [[String: Any]] else {
            return nil
        }
        for item in contents {
            if let text = item["text"] as? String, !text.isEmpty {
                return text
            }
            if let blob = item["blob"] as? String, !blob.isEmpty {
                return blob
            }
        }
        return nil
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

        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw MCPTransportError.decodeError(error.localizedDescription)
        }
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
