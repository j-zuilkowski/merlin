# Phase 43b — Connectors Implementation (GitHub, Slack, Linear)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 43a complete: failing ConnectorTests in place.

---

## Write to: Merlin/Connectors/ConnectorCredentials.swift

```swift
import Foundation
import Security

enum ConnectorCredentials {
    private static let prefix = "com.merlin.connector."

    static func store(token: String, service: String) throws {
        let key = prefix + service
        let data = token.data(using: .utf8)!
        // Delete existing if present
        try? delete(service: service)
        let query: [CFString: Any] = [
            kSecClass:           kSecClassGenericPassword,
            kSecAttrService:     key,
            kSecAttrAccount:     service,
            kSecValueData:       data,
            kSecAttrAccessible:  kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    static func retrieve(service: String) -> String? {
        let key = prefix + service
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      key,
            kSecAttrAccount:      service,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8)
        else { return nil }
        return token
    }

    static func delete(service: String) throws {
        let key = prefix + service
        let query: [CFString: Any] = [
            kSecClass:        kSecClassGenericPassword,
            kSecAttrService:  key,
            kSecAttrAccount:  service,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}
```

---

## Write to: Merlin/Connectors/Connector.swift

```swift
import Foundation

protocol Connector: Sendable {
    var token: String { get }
    var isConfigured: Bool { get }
    init(token: String)
}

extension Connector {
    var isConfigured: Bool { !token.trimmingCharacters(in: .whitespaces).isEmpty }
}
```

---

## Write to: Merlin/Connectors/GitHubConnector.swift

```swift
import Foundation

final class GitHubConnector: Connector, @unchecked Sendable {
    let token: String
    init(token: String) { self.token = token }

    private let baseURL = "https://api.github.com"

    // MARK: - Read

    func listOpenPRs(owner: String, repo: String) async throws -> [[String: Any]] {
        try await get("/repos/\(owner)/\(repo)/pulls?state=open&per_page=30")
    }

    func getIssue(owner: String, repo: String, number: Int) async throws -> [String: Any] {
        try await getOne("/repos/\(owner)/\(repo)/issues/\(number)")
    }

    func getFileContents(owner: String, repo: String, path: String, ref: String = "HEAD") async throws -> String {
        let json: [String: Any] = try await getOne("/repos/\(owner)/\(repo)/contents/\(path)?ref=\(ref)")
        guard let encoded = json["content"] as? String else { return "" }
        let cleaned = encoded.replacingOccurrences(of: "\n", with: "")
        guard let data = Data(base64Encoded: cleaned) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Write

    func createPR(owner: String, repo: String, title: String, body: String,
                  head: String, base: String) async throws -> [String: Any] {
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

    // MARK: - HTTP helpers

    private func get(_ path: String) async throws -> [[String: Any]] {
        let data = try await fetch(path: path, method: "GET", body: nil)
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    private func getOne(_ path: String) async throws -> [String: Any] {
        let data = try await fetch(path: path, method: "GET", body: nil)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func post(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        let bd = try JSONSerialization.data(withJSONObject: body)
        let data = try await fetch(path: path, method: "POST", body: bd)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func put(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        let bd = try JSONSerialization.data(withJSONObject: body)
        let data = try await fetch(path: path, method: "PUT", body: bd)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func fetch(path: String, method: String, body: Data?) async throws -> Data {
        var req = URLRequest(url: URL(string: baseURL + path)!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let b = body {
            req.httpBody = b
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, _) = try await URLSession.shared.data(for: req)
        return data
    }
}
```

---

## Write to: Merlin/Connectors/SlackConnector.swift

```swift
import Foundation

final class SlackConnector: Connector, @unchecked Sendable {
    let token: String
    init(token: String) { self.token = token }

    /// Fetch recent messages from a channel (by channel ID or name).
    func listMessages(channel: String, limit: Int = 20) async throws -> [[String: Any]] {
        let url = URL(string: "https://slack.com/api/conversations.history?channel=\(channel)&limit=\(limit)")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return json["messages"] as? [[String: Any]] ?? []
    }

    /// Post a message to a channel.
    func postMessage(channel: String, text: String) async throws {
        var req = URLRequest(url: URL(string: "https://slack.com/api/chat.postMessage")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["channel": channel, "text": text])
        _ = try await URLSession.shared.data(for: req)
    }
}
```

---

## Write to: Merlin/Connectors/LinearConnector.swift

```swift
import Foundation

final class LinearConnector: Connector, @unchecked Sendable {
    let token: String
    init(token: String) { self.token = token }

    private let endpoint = URL(string: "https://api.linear.app/graphql")!

    // MARK: - Read

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

    // MARK: - GraphQL helper

    private func graphql(query: String) async throws -> [String: Any] {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return json["data"] as? [String: Any] ?? [:]
    }
}
```

---

## Write to: Merlin/Views/ConnectorsView.swift

```swift
import SwiftUI

struct ConnectorsView: View {
    @State private var githubToken  = ConnectorCredentials.retrieve(service: "github")  ?? ""
    @State private var slackToken   = ConnectorCredentials.retrieve(service: "slack")   ?? ""
    @State private var linearToken  = ConnectorCredentials.retrieve(service: "linear")  ?? ""
    @State private var saveStatus   = ""

    var body: some View {
        Form {
            Section("GitHub") {
                SecureField("Personal Access Token", text: $githubToken)
                    .textContentType(.password)
                Text("Required for PR monitoring and GitHub tool calls.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Slack") {
                SecureField("Bot Token (xoxb-…)", text: $slackToken)
                    .textContentType(.password)
            }
            Section("Linear") {
                SecureField("API Key", text: $linearToken)
                    .textContentType(.password)
            }
            if !saveStatus.isEmpty {
                Text(saveStatus).foregroundStyle(.secondary).font(.caption)
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
        .frame(minWidth: 400)
        .navigationTitle("Connectors")
    }

    private func save() {
        saveToken(githubToken, service: "github")
        saveToken(slackToken,  service: "slack")
        saveToken(linearToken, service: "linear")
        saveStatus = "Saved"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saveStatus = "" }
    }

    private func saveToken(_ token: String, service: String) {
        if token.isEmpty {
            try? ConnectorCredentials.delete(service: service)
        } else {
            try? ConnectorCredentials.store(token: token, service: service)
        }
    }
}
```

---

## Modify: project.yml

Add to Merlin target sources:
- `Merlin/Connectors/ConnectorCredentials.swift`
- `Merlin/Connectors/Connector.swift`
- `Merlin/Connectors/GitHubConnector.swift`
- `Merlin/Connectors/SlackConnector.swift`
- `Merlin/Connectors/LinearConnector.swift`
- `Merlin/Views/ConnectorsView.swift`

```bash
cd ~/Documents/localProject/merlin
xcodegen generate
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: `BUILD SUCCEEDED`; `ConnectorCredentialsTests` → 4 tests pass;
`ConnectorProtocolTests` → 5 tests pass; all prior tests pass.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Connectors/ConnectorCredentials.swift \
        Merlin/Connectors/Connector.swift \
        Merlin/Connectors/GitHubConnector.swift \
        Merlin/Connectors/SlackConnector.swift \
        Merlin/Connectors/LinearConnector.swift \
        Merlin/Views/ConnectorsView.swift \
        project.yml
git commit -m "Phase 43b — GitHub + Slack + Linear connectors + ConnectorCredentials"
```
