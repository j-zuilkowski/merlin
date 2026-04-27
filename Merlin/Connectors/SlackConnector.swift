import Foundation

final class SlackConnector: Connector, @unchecked Sendable {
    let token: String

    init(token: String) {
        self.token = token
    }

    func listMessages(channel: String, limit: Int = 20) async throws -> [[String: Any]] {
        let url = URL(string: "https://slack.com/api/conversations.history?channel=\(channel)&limit=\(limit)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return json["messages"] as? [[String: Any]] ?? []
    }

    func postMessage(channel: String, text: String) async throws {
        var request = URLRequest(url: URL(string: "https://slack.com/api/chat.postMessage")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "channel": channel,
            "text": text
        ])
        _ = try await URLSession.shared.data(for: request)
    }
}
