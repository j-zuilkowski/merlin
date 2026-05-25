# Phase 43a — Connectors Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 42b complete: PRMonitor GitHub polling + CI status + auto-merge.

New surface introduced in phase 43b:
  - `ConnectorCredentials` — stores one token per service in Keychain
    (`com.merlin.connector.<service>`)
  - `GitHubConnector` — read: list PRs, get issue, get file contents;
    write: create PR, post comment, merge PR, push via git CLI
  - `SlackConnector` — read: list messages from configured channels;
    write: post message
  - `LinearConnector` — read: list issues, project status;
    write: create issue, update status, post comment
  - All connectors conform to `Connector` protocol:
    `init(token: String)`; `isConfigured: Bool`

TDD coverage:
  File 1 — ConnectorCredentialsTests: store/retrieve/delete per service; missing returns nil
  File 2 — ConnectorProtocolTests: isConfigured false when token empty; true when non-empty

---

## Write to: MerlinTests/Unit/ConnectorTests.swift

```swift
import XCTest
@testable import Merlin

final class ConnectorCredentialsTests: XCTestCase {

    private let service = "test-\(UUID().uuidString)"

    override func tearDown() {
        try? ConnectorCredentials.delete(service: service)
        super.tearDown()
    }

    func testStoreAndRetrieve() throws {
        try ConnectorCredentials.store(token: "tok123", service: service)
        let retrieved = ConnectorCredentials.retrieve(service: service)
        XCTAssertEqual(retrieved, "tok123")
    }

    func testRetrieveMissingReturnsNil() {
        let result = ConnectorCredentials.retrieve(service: "definitely-does-not-exist-\(UUID().uuidString)")
        XCTAssertNil(result)
    }

    func testDeleteRemovesToken() throws {
        try ConnectorCredentials.store(token: "tok", service: service)
        try ConnectorCredentials.delete(service: service)
        XCTAssertNil(ConnectorCredentials.retrieve(service: service))
    }

    func testOverwriteExistingToken() throws {
        try ConnectorCredentials.store(token: "old", service: service)
        try ConnectorCredentials.store(token: "new", service: service)
        XCTAssertEqual(ConnectorCredentials.retrieve(service: service), "new")
    }
}

final class ConnectorProtocolTests: XCTestCase {

    func testGitHubConnectorIsConfiguredWhenTokenNonEmpty() {
        let connector = GitHubConnector(token: "ghp_token123")
        XCTAssertTrue(connector.isConfigured)
    }

    func testGitHubConnectorNotConfiguredWhenTokenEmpty() {
        let connector = GitHubConnector(token: "")
        XCTAssertFalse(connector.isConfigured)
    }

    func testSlackConnectorIsConfiguredWhenTokenNonEmpty() {
        let connector = SlackConnector(token: "xoxb-token")
        XCTAssertTrue(connector.isConfigured)
    }

    func testLinearConnectorIsConfiguredWhenTokenNonEmpty() {
        let connector = LinearConnector(token: "lin_api_token")
        XCTAssertTrue(connector.isConfigured)
    }

    func testLinearConnectorNotConfiguredWhenTokenEmpty() {
        let connector = LinearConnector(token: "")
        XCTAssertFalse(connector.isConfigured)
    }
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD FAILED` with errors referencing `ConnectorCredentials`, `GitHubConnector`,
`SlackConnector`, `LinearConnector`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/ConnectorTests.swift
git commit -m "Phase 43a — ConnectorTests (failing)"
```
