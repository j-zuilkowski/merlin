# Phase 05 — KeychainManager

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. 37 tools total.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin

---

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

---

## Write to: MerlinTests/Unit/KeychainTests.swift

```swift
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
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/KeychainTests 2>&1 | grep -E 'passed|failed|error:|BUILD'
```

Expected: `Test Suite 'KeychainTests' passed` with 3 tests.

Also confirm no key values appear in output:
```bash
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/KeychainTests 2>&1 | grep -v 'sk-test-123' | wc -l
```

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Keychain/KeychainManager.swift MerlinTests/Unit/KeychainTests.swift
git commit -m "Phase 05 — KeychainManager + tests"
```
