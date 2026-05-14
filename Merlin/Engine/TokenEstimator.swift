import Foundation

enum TokenEstimator {
    static func estimate(
        request: CompletionRequest,
        baseURL: URL = URL(string: "http://localhost")!,
        modelID: String = ""
    ) -> Int {
        let bytes = (try? encodeRequest(request, baseURL: baseURL, model: modelID))?.count ?? 0
        return Int(ceil(Double(bytes) / 4.0 * 1.2)) + 512
    }
}
