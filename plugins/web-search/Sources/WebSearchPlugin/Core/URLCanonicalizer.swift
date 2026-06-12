import Foundation

enum URLCanonicalizer {
    static func canonicalize(_ raw: String) -> String {
        guard var components = URLComponents(string: raw) else {
            return raw
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        if let queryItems = components.queryItems {
            let filtered = queryItems.filter { item in
                let name = item.name.lowercased()
                return name.hasPrefix("utm_") == false && name != "fbclid" && name != "gclid"
            }
            components.queryItems = filtered.isEmpty ? nil : filtered
        }
        var result = components.url?.absoluteString ?? raw
        if result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }
}
