# Phase 05 — KeychainManager

Context: HANDOFF.md.

## Write to: Merlin/Keychain/KeychainManager.swift

```swift
import Security
import Foundation

enum KeychainManager {
    static let service = "com.merlin.deepseek"
    static let account = "api-key"

    // Returns nil if no key stored
    static func readAPIKey() -> String?

    // Overwrites if key already exists
    static func writeAPIKey(_ key: String) throws

    static func deleteAPIKey() throws
}
```

Use `SecItemCopyMatching`, `SecItemAdd`, `SecItemUpdate`, `SecItemDelete`.
Never log the key value.

## Write to: MerlinTests/Unit/KeychainTests.swift

```swift
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
```

## Acceptance
- [ ] `swift test --filter KeychainTests` — all 3 pass
- [ ] Key is never printed to stdout/stderr in any code path
