# Task 05 — KeychainManager

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. Dynamic tool registry (ToolRegistry actor).
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
git commit -m "Task 05 — KeychainManager + tests"
```

---

## Current Implementation (2026-05-06) — File-based storage

**`KeychainManager` no longer uses the macOS Keychain.** Keys are stored in
`~/.merlin/api-keys.json` (chmod 0600, owner read/write only).

### Why
Ad-hoc rebuilt binaries get a new code-signing identity on every build. The macOS
file-based Keychain ties item ACLs to the writing process's identity (cdhash), so every
rebuild produces an ACL mismatch that silently appears as "no API key configured".
File-based storage (the same pattern as `~/.aws/credentials`, `~/.config/gh/hosts.yml`)
has no identity dependency and survives all rebuilds trivially.

### Migration
On first read, if a key exists in the legacy Keychain under `com.merlin.api-keys`, it is
silently migrated to the file store and the Keychain item is deleted.

### TODO — restore Keychain storage
When Merlin is distributed with a stable Developer ID signature (not ad-hoc), revert
`KeychainManager` to Keychain-based storage using `kSecUseDataProtectionKeychain: true`
(the modern user-scoped Data Protection Keychain, not the legacy file-based one). Items
in the Data Protection Keychain are tied to the user account, not the signing identity,
so they survive rebuilds. At that point, add a one-time migration that reads from
`~/.merlin/api-keys.json` and writes each key into the Data Protection Keychain, then
deletes the file.

---

## Fixes

### 2026-05-06 — Remove self-destructing migration in ProviderConfig (commit de82690)

**Problem:** `ProviderRegistry.init` called a private static method `migrateFileKeysToKeychain(knownProviderIDs:)`. This method read `~/.merlin/api-keys.json`, checked if each key already existed via `KeychainManager.readAPIKey(for:)` (which now reads from the file), found the key present, skipped the write, then called `FileManager.removeItem(at:)` on the file — deleting the API key on every launch.

**Fix:** Removed the `migrateFileKeysToKeychain` call and the function entirely from `ProviderConfig.swift`. `KeychainManager` is the file store; no migration path is needed. `ProviderRegistry.init` now does a single `readAPIKey` pass to populate `keyedProviderIDs` without any secondary migration step.
