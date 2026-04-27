# Phase 46a — AppSettings Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 45b complete: ToolRegistry in place.

New surface introduced in phase 46b:
  - `AppSettings` — @MainActor ObservableObject singleton; single source of truth for all config
  - `AppSettings.shared` — singleton
  - `AppSettings.load(from url: URL) async throws` — reads config.toml via TOMLDecoder
  - `AppSettings.save(to url: URL) async throws` — writes config.toml (TOML serialization)
  - `AppSettings.propose(_ change: SettingsProposal) async -> Bool` — agent-initiated change with user approval
  - `SettingsProposal` — enum of possible agent-proposed changes
  - `AppSettings.startWatching(url: URL)` — FSEvents watcher for live external edits
  - Key persisted fields: `autoCompact: Bool`, `providerName: String`, `modelID: String`,
    `maxTokens: Int`, `standingInstructions: String`, hooks array, providers array
  - `AppearanceSettings` — struct: `fontSize: Double`, `fontName: String`, `accentColorHex: String`,
    `theme: AppTheme` (system/light/dark)
  - `AppTheme` — enum: `system`, `light`, `dark`

TDD coverage:
  File 1 — AppSettingsTests: load from TOML file, save round-trip, default values, propose/approve,
           propose/deny, appearance defaults, FSEvents callback triggers reload

---

## Write to: MerlinTests/Unit/AppSettingsTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class AppSettingsTests: XCTestCase {

    private var tmpURL: URL!
    private var settings: AppSettings!

    override func setUp() async throws {
        tmpURL = URL(fileURLWithPath: "/tmp/merlin-test-config-\(UUID().uuidString).toml")
        settings = AppSettings()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpURL)
        settings.stopWatching()
    }

    // MARK: - Defaults

    func test_defaults_autoCompactFalse() {
        XCTAssertFalse(settings.autoCompact)
    }

    func test_defaults_maxTokensPositive() {
        XCTAssertGreaterThan(settings.maxTokens, 0)
    }

    func test_defaults_standingInstructionsEmpty() {
        XCTAssertTrue(settings.standingInstructions.isEmpty)
    }

    func test_defaults_appearance_themeSystem() {
        XCTAssertEqual(settings.appearance.theme, .system)
    }

    // MARK: - Load from TOML

    func test_load_parsesAutoCompact() async throws {
        try "auto_compact = true\n".write(to: tmpURL, atomically: true, encoding: .utf8)
        try await settings.load(from: tmpURL)
        XCTAssertTrue(settings.autoCompact)
    }

    func test_load_parsesMaxTokens() async throws {
        try "max_tokens = 8192\n".write(to: tmpURL, atomically: true, encoding: .utf8)
        try await settings.load(from: tmpURL)
        XCTAssertEqual(settings.maxTokens, 8192)
    }

    func test_load_parsesStandingInstructions() async throws {
        try #"standing_instructions = "Be concise.""# .write(to: tmpURL, atomically: true, encoding: .utf8)
        try await settings.load(from: tmpURL)
        XCTAssertEqual(settings.standingInstructions, "Be concise.")
    }

    func test_load_parsesAppearanceTheme() async throws {
        let toml = """
        [appearance]
        theme = "dark"
        font_size = 14.0
        """
        try toml.write(to: tmpURL, atomically: true, encoding: .utf8)
        try await settings.load(from: tmpURL)
        XCTAssertEqual(settings.appearance.theme, .dark)
        XCTAssertEqual(settings.appearance.fontSize, 14.0, accuracy: 0.001)
    }

    func test_load_parsesHooksArray() async throws {
        let toml = """
        [[hooks]]
        event = "PreToolUse"
        command = "/usr/local/bin/check"

        [[hooks]]
        event = "Stop"
        command = "/usr/local/bin/cleanup"
        """
        try toml.write(to: tmpURL, atomically: true, encoding: .utf8)
        try await settings.load(from: tmpURL)
        XCTAssertEqual(settings.hooks.count, 2)
        XCTAssertEqual(settings.hooks[0].event, "PreToolUse")
        XCTAssertEqual(settings.hooks[1].command, "/usr/local/bin/cleanup")
    }

    func test_load_missingFileUsesDefaults() async throws {
        let absent = URL(fileURLWithPath: "/tmp/no-such-file-\(UUID().uuidString).toml")
        // Should not throw — missing file silently uses defaults
        try await settings.load(from: absent)
        XCTAssertFalse(settings.autoCompact)
    }

    // MARK: - Save / round-trip

    func test_save_roundTrip() async throws {
        settings.autoCompact = true
        settings.maxTokens = 4096
        settings.standingInstructions = "Always reply in English."
        try await settings.save(to: tmpURL)

        let reloaded = AppSettings()
        try await reloaded.load(from: tmpURL)
        XCTAssertTrue(reloaded.autoCompact)
        XCTAssertEqual(reloaded.maxTokens, 4096)
        XCTAssertEqual(reloaded.standingInstructions, "Always reply in English.")
    }

    // MARK: - SettingsProposal

    func test_propose_approvedByUser() async {
        // Inject an approver that always says yes
        settings.proposalApprover = { _ in return true }
        let accepted = await settings.propose(.setMaxTokens(2048))
        XCTAssertTrue(accepted)
        XCTAssertEqual(settings.maxTokens, 2048)
    }

    func test_propose_deniedByUser() async {
        settings.proposalApprover = { _ in return false }
        let originalMax = settings.maxTokens
        let accepted = await settings.propose(.setMaxTokens(9999))
        XCTAssertFalse(accepted)
        XCTAssertEqual(settings.maxTokens, originalMax)
    }

    func test_propose_standingInstructions() async {
        settings.proposalApprover = { _ in return true }
        let accepted = await settings.propose(.setStandingInstructions("Always use bullet points."))
        XCTAssertTrue(accepted)
        XCTAssertEqual(settings.standingInstructions, "Always use bullet points.")
    }

    // MARK: - AppTheme

    func test_appTheme_allCasesDecodable() {
        XCTAssertEqual(AppTheme(rawValue: "system"), .system)
        XCTAssertEqual(AppTheme(rawValue: "light"), .light)
        XCTAssertEqual(AppTheme(rawValue: "dark"), .dark)
        XCTAssertNil(AppTheme(rawValue: "unknown"))
    }
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD FAILED — `AppSettings`, `AppearanceSettings`, `AppTheme`, `SettingsProposal` not yet defined.

## Commit
```bash
git add MerlinTests/Unit/AppSettingsTests.swift
git commit -m "Phase 46a — AppSettingsTests (failing)"
```
