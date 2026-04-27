import Foundation

final class LinearConnector: Connector, @unchecked Sendable {
    let token: String

    init(token: String) {
        self.token = token
    }

    func listIssues(teamID: String, limit: Int = 20) async throws -> [[String: Any]] {
        let query = """
        { issues(filter: { team: { id: { eq: "\(teamID)" } } }, first: \(limit)) {
            nodes { id title state { name } url } } }
        """
        let result = try await graphql(query: query)
        return (result["issues"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
    }

    func createIssue(teamID: String, title: String, description: String) async throws -> [String: Any] {
        let mutation = """
        mutation { issueCreate(input: {
            teamId: "\(teamID)", title: "\(title)", description: "\(description)"
        }) { issue { id title url } } }
        """
        let result = try await graphql(query: mutation)
        return (result["issueCreate"] as? [String: Any])?["issue"] as? [String: Any] ?? [:]
    }

    func updateStatus(issueID: String, stateID: String) async throws {
        let mutation = """
        mutation { issueUpdate(id: "\(issueID)", input: { stateId: "\(stateID)" }) { success } }
        """
        _ = try await graphql(query: mutation)
    }

    func postComment(issueID: String, body: String) async throws {
        let mutation = """
        mutation { commentCreate(input: { issueId: "\(issueID)", body: "\(body)" }) { success } }
        """
        _ = try await graphql(query: mutation)
    }

    private func graphql(query: String) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://api.linear.app/graphql")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return json["data"] as? [String: Any] ?? [:]
    }
}
