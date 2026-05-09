//  XcalibreKAGPlugin.swift — KAGBackendPlugin backed by xcalibre-server REST API.
//
//  Calls:
//    POST /api/v1/graph/triples  (ingest session triples)
//    GET  /api/v1/graph/traverse (BFS traversal)
//
//  All calls use a Bearer token. 10-second timeout. Silent failure is NOT the goal
//  here — callers decide whether to propagate or swallow.

import Foundation

public final class XcalibreKAGPlugin: KAGBackendPlugin, @unchecked Sendable {

    private let baseURL: URL
    private let token:   String
    private let session: URLSession

    public init(baseURL: URL, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token   = token
        self.session = session
    }

    // MARK: - Write

    public func writeTriples(_ triples: [KAGTriple]) async throws {
        guard !triples.isEmpty else { return }

        let url = baseURL.appendingPathComponent("/api/v1/graph/triples")
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let payload = WritePayload(triples: triples.map {
            TripleDTO(subject: $0.subject, predicate: $0.predicate, object: $0.object,
                      domain_id: $0.domainId, session_id: "", confidence: $0.confidence)
        })
        let body = try JSONEncoder().encode(payload)
        req.httpBody = body

        let response = try await performDataTask(request: req).1
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw XcalibreKAGError.badStatus(code)
        }
    }

    // MARK: - Traverse

    public func traverse(anchor: String, hops: Int, domainId: String?) async throws -> [KAGTriple] {
        var components = URLComponents(url: baseURL.appendingPathComponent("/api/v1/graph/traverse"),
                                       resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            .init(name: "anchor", value: anchor),
            .init(name: "hops",   value: "\(hops)"),
        ]
        if let d = domainId, !d.isEmpty {
            items.append(.init(name: "domain_id", value: d))
        }
        components.queryItems = items

        var req = URLRequest(url: components.url!, timeoutInterval: 10)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await performDataTask(request: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw XcalibreKAGError.badStatus(code)
        }

        let envelope = try JSONDecoder().decode(TraverseEnvelope.self, from: data)
        return envelope.triples.map {
            KAGTriple(subject: $0.subject, predicate: $0.predicate, object: $0.object,
                      domainId: $0.domain_id,
                      source: KAGTripleSource(rawValue: $0.source) ?? .session,
                      confidence: $0.confidence)
        }
    }

    // MARK: - Codable helpers

    private struct WritePayload: Encodable {
        let triples: [TripleDTO]
    }

    private struct TripleDTO: Encodable {
        let subject:    String
        let predicate:  String
        let object:     String
        let domain_id:  String
        let session_id: String
        let confidence: Double
    }

    private struct TraverseEnvelope: Decodable {
        let triples: [ServerTriple]
    }

    private struct ServerTriple: Decodable {
        let subject:     String
        let predicate:   String
        let object:      String
        let domain_id:   String
        let source:      String
        let confidence:  Double
    }

    private func performDataTask(request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data, let response else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                continuation.resume(returning: (data, response))
            }
            task.resume()
        }
    }
}

enum XcalibreKAGError: Error {
    case badStatus(Int)
}
