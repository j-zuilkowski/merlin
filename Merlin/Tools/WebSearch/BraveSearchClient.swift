import Foundation

struct BraveSearchResult: Sendable {
    let title: String
    let url: String
    let description: String
}

protocol BraveSearchClientProtocol: Sendable {
    func search(query: String, count: Int) async throws -> [BraveSearchResult]
}

actor BraveSearchClient: BraveSearchClientProtocol {
    private let apiKey: String
    private let session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func search(query: String, count: Int = 10) async throws -> [BraveSearchResult] {
        var components = URLComponents(string: "https://api.search.brave.com/res/v1/web/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: String(min(max(count, 1), 20)))
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.addValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let web = json["web"] as? [String: Any],
              let results = web["results"] as? [[String: Any]] else {
            return []
        }

        return results.compactMap { item in
            guard let title = item["title"] as? String,
                  let url = item["url"] as? String else {
                return nil
            }
            let description = item["description"] as? String ?? ""
            return BraveSearchResult(title: title, url: url, description: description)
        }
    }
}
