import Foundation

protocol SearchProvider: Sendable {
    var id: String { get }
    func search(_ request: SearchRequest, settings: WebSearchSettings) async -> SearchProviderResult
}

extension SearchProvider {
    func disabledResult(message: String) -> SearchProviderResult {
        SearchProviderResult(
            providerID: id,
            results: [],
            diagnostic: ProviderDiagnostic(providerID: id, state: .disabled, message: message)
        )
    }
}
