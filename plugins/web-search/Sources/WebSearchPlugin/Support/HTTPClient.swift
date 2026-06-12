import Foundation

struct HTTPResponse: Sendable {
    var url: URL
    var statusCode: Int
    var headers: [String: String]
    var data: Data

    func header(_ name: String) -> String? {
        let lower = name.lowercased()
        return headers.first { $0.key.lowercased() == lower }?.value
    }
}

protocol HTTPClient: Sendable {
    func request(_ url: URL, method: String, headers: [String: String], body: Data?, timeout: TimeInterval, maxBytes: Int?) async throws -> HTTPResponse
    func get(_ url: URL, headers: [String: String], timeout: TimeInterval, maxBytes: Int?) async throws -> HTTPResponse
}

extension HTTPClient {
    func get(_ url: URL, headers: [String: String], timeout: TimeInterval, maxBytes: Int?) async throws -> HTTPResponse {
        try await request(url, method: "GET", headers: headers, body: nil, timeout: timeout, maxBytes: maxBytes)
    }

    func post(_ url: URL, headers: [String: String], body: Data, timeout: TimeInterval, maxBytes: Int?) async throws -> HTTPResponse {
        try await request(url, method: "POST", headers: headers, body: body, timeout: timeout, maxBytes: maxBytes)
    }
}

enum HTTPClientError: Error, Equatable {
    case invalidResponse
    case tooLarge(Int)
}

struct URLSessionHTTPClient: HTTPClient {
    func request(_ url: URL, method: String, headers: [String: String], body: Data?, timeout: TimeInterval, maxBytes: Int?) async throws -> HTTPResponse {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HTTPClientError.invalidResponse
        }
        if let maxBytes, data.count > maxBytes {
            throw HTTPClientError.tooLarge(data.count)
        }
        var responseHeaders: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            responseHeaders[String(describing: key)] = String(describing: value)
        }
        return HTTPResponse(url: http.url ?? url, statusCode: http.statusCode, headers: responseHeaders, data: data)
    }
}

final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    private var responses: [String: HTTPResponse]

    init(responses: [String: HTTPResponse]) {
        self.responses = responses
    }

    func request(_ url: URL, method: String, headers: [String: String], body: Data?, timeout: TimeInterval, maxBytes: Int?) async throws -> HTTPResponse {
        let response = responses["\(method.uppercased()) \(url.absoluteString)"] ?? responses[url.absoluteString]
        guard let response else {
            throw URLError(.fileDoesNotExist)
        }
        if let maxBytes, response.data.count > maxBytes {
            throw HTTPClientError.tooLarge(response.data.count)
        }
        return response
    }
}
