import Foundation

func normalizedOpenAICompatibleBaseURL(_ baseURL: URL) -> URL {
    let trimmedPath = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    if trimmedPath.isEmpty {
        return baseURL.appendingPathComponent("v1")
    }
    if trimmedPath.hasSuffix("v1") {
        return baseURL
    }
    return baseURL.appendingPathComponent("v1")
}

func shellQuote(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}
