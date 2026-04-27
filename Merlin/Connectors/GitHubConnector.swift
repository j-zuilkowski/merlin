import Foundation

final class GitHubConnector: Connector, @unchecked Sendable {
    let token: String

    init(token: String) {
        self.token = token
    }

    func listOpenPRs(owner: String, repo: String) async throws -> [[String: Any]] {
        try await get("/repos/\(owner)/\(repo)/pulls?state=open&per_page=30")
    }

    func getIssue(owner: String, repo: String, number: Int) async throws -> [String: Any] {
        try await getOne("/repos/\(owner)/\(repo)/issues/\(number)")
    }

    func getFileContents(owner: String, repo: String, path: String, ref: String = "HEAD") async throws -> String {
        let json: [String: Any] = try await getOne("/repos/\(owner)/\(repo)/contents/\(path)?ref=\(ref)")
        guard let encoded = json["content"] as? String else {
            return ""
        }
        let cleaned = encoded.replacingOccurrences(of: "\n", with: "")
        guard let data = Data(base64Encoded: cleaned) else {
            return ""
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func createPR(owner: String,
                  repo: String,
                  title: String,
                  body: String,
                  head: String,
                  base: String) async throws -> [String: Any] {
        try await post("/repos/\(owner)/\(repo)/pulls",
                       body: ["title": title, "body": body, "head": head, "base": base])
    }

    func postComment(owner: String, repo: String, issueNumber: Int, body: String) async throws {
        _ = try await post("/repos/\(owner)/\(repo)/issues/\(issueNumber)/comments",
                           body: ["body": body])
    }

    func mergePR(owner: String, repo: String, number: Int, method: String = "squash") async throws {
        _ = try await put("/repos/\(owner)/\(repo)/pulls/\(number)/merge",
                          body: ["merge_method": method])
    }

    private func get(_ path: String) async throws -> [[String: Any]] {
        let data = try await fetch(path: path, method: "GET", body: nil)
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    private func getOne(_ path: String) async throws -> [String: Any] {
        let data = try await fetch(path: path, method: "GET", body: nil)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func post(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: body)
        let response = try await fetch(path: path, method: "POST", body: data)
        return (try? JSONSerialization.jsonObject(with: response) as? [String: Any]) ?? [:]
    }

    private func put(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: body)
        let response = try await fetch(path: path, method: "PUT", body: data)
        return (try? JSONSerialization.jsonObject(with: response) as? [String: Any]) ?? [:]
    }

    private func fetch(path: String, method: String, body: Data?) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.github.com" + path)!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }
}
