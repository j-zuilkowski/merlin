import Foundation
import XCTest
@testable import WebSearchPlugin

func fixtureData(_ name: String, _ ext: String) throws -> Data {
    let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

func fixtureString(_ name: String, _ ext: String) throws -> String {
    try String(data: fixtureData(name, ext), encoding: .utf8).unwrap()
}

extension Optional {
    func unwrap(file: StaticString = #filePath, line: UInt = #line) throws -> Wrapped {
        try XCTUnwrap(self, file: file, line: line)
    }
}

final class StubProvider: SearchProvider, @unchecked Sendable {
    let id: String
    let url: String
    let title: String
    let snippet: String
    let score: Double
    let retrievedAt: Date

    init(
        id: String,
        url: String,
        title: String,
        snippet: String = "",
        score: Double = 100,
        retrievedAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.snippet = snippet
        self.score = score
        self.retrievedAt = retrievedAt
    }

    func search(_ request: SearchRequest, settings: WebSearchSettings) async -> SearchProviderResult {
        let result = SearchResult(title: title, url: url, canonicalURL: URLCanonicalizer.canonicalize(url), snippet: snippet, providerID: id, rank: 1, score: score, retrievedAt: retrievedAt, diagnostics: [])
        return SearchProviderResult(providerID: id, results: [result], diagnostic: ProviderDiagnostic(providerID: id, state: .ok, message: "ok"))
    }
}

final class CountingProvider: SearchProvider, @unchecked Sendable {
    let id = "duckduckgo_lite"
    private(set) var count = 0

    func search(_ request: SearchRequest, settings: WebSearchSettings) async -> SearchProviderResult {
        count += 1
        let result = SearchResult(title: "Cached", url: "https://example.com/cache", canonicalURL: "https://example.com/cache", snippet: "", providerID: id, rank: 1, score: 100, retrievedAt: Date(), diagnostics: [])
        return SearchProviderResult(providerID: id, results: [result], diagnostic: ProviderDiagnostic(providerID: id, state: .ok, message: "ok"))
    }
}

struct StubExtractor: PageExtractionProvider {
    let id = "extractor"

    func extract(_ request: PageExtractionRequest, settings: WebSearchSettings) async -> PageExtractionResult {
        PageExtractionResult(requestedURL: request.url, finalURL: request.url, contentType: "text/html", byteCount: 42, title: "Title", text: "Extracted text", strategy: "stub", truncated: false, diagnostics: [ProviderDiagnostic(providerID: id, state: .ok, message: "ok")], cached: false)
    }
}
