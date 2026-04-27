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
