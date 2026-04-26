import XCTest
@testable import Merlin

final class KeychainTests: XCTestCase {

    override func setUp() { try? KeychainManager.deleteAPIKey() }
    override func tearDown() { try? KeychainManager.deleteAPIKey() }

    func testWriteAndRead() throws {
        try KeychainManager.writeAPIKey("sk-test-123")
        XCTAssertEqual(KeychainManager.readAPIKey(), "sk-test-123")
    }

    func testReadMissingReturnsNil() {
        XCTAssertNil(KeychainManager.readAPIKey())
    }

    func testOverwrite() throws {
        try KeychainManager.writeAPIKey("old")
        try KeychainManager.writeAPIKey("new")
        XCTAssertEqual(KeychainManager.readAPIKey(), "new")
    }
}
