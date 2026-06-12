import Foundation

struct BoundedFallbackPageExtractor: PageExtractionProvider {
    let id = "bounded_fallback"
    let primary: any PageExtractionProvider
    let fallback: any PageExtractionProvider

    func extract(_ request: PageExtractionRequest, settings: WebSearchSettings) async -> PageExtractionResult {
        let primaryResult = await primary.extract(request, settings: settings)
        guard settings.webkitExtractionEnabled,
              shouldFallback(primaryResult) else {
            return primaryResult
        }
        let fallbackResult = await fallback.extract(request, settings: settings)
        var diagnostics = primaryResult.diagnostics
        diagnostics.append(contentsOf: fallbackResult.diagnostics)
        var merged = fallbackResult
        merged.diagnostics = diagnostics
        return merged
    }

    private func shouldFallback(_ result: PageExtractionResult) -> Bool {
        guard let state = result.diagnostics.first?.state else { return false }
        return state == .javascriptRequired || state == .parseFailed
    }
}
