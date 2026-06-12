import Foundation

struct PageExtractionRequest: Codable, Sendable, Equatable {
    var url: String
    var settings: WebSearchSettings?

    init(url: String, settings: WebSearchSettings? = nil) {
        self.url = url
        self.settings = settings
    }
}

struct PageExtractionResult: Codable, Sendable, Equatable {
    var requestedURL: String
    var finalURL: String
    var contentType: String?
    var byteCount: Int
    var title: String?
    var text: String
    var strategy: String
    var truncated: Bool
    var diagnostics: [ProviderDiagnostic]
    var cached: Bool
}

protocol PageExtractionProvider: Sendable {
    var id: String { get }
    func extract(_ request: PageExtractionRequest, settings: WebSearchSettings) async -> PageExtractionResult
}
