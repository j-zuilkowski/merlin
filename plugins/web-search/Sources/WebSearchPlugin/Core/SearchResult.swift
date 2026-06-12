import Foundation

struct SearchResult: Codable, Sendable, Equatable {
    var title: String
    var url: String
    var canonicalURL: String
    var snippet: String
    var providerID: String
    var rank: Int
    var score: Double
    var retrievedAt: Date
    var diagnostics: [ProviderDiagnostic]
}

struct SearchProviderResult: Codable, Sendable, Equatable {
    var providerID: String
    var results: [SearchResult]
    var diagnostic: ProviderDiagnostic
}

struct SearchResponse: Codable, Sendable, Equatable {
    var query: String
    var results: [SearchResult]
    var diagnostics: [ProviderDiagnostic]
    var cached: Bool
    var generatedAt: Date
}
