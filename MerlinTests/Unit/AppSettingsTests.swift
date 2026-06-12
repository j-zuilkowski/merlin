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
        try #"standing_instructions = "Be concise.""#.write(to: tmpURL, atomically: true, encoding: .utf8)
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

    func test_load_parsesSlotsWhenLlamaCppSectionIsPresent() async throws {
        let toml = """
        [slots]
        execute = "llamacpp:qwen3-coder-local"
        reason = "deepseek"
        orchestrate = "deepseek"
        vision = "llamacpp:qwen3-vl-local"

        [llamacpp]
        server_path = "/opt/homebrew/bin/llama-server"
        router_enabled = true
        models_preset_path = "/tmp/ampdemo-llamacpp/llamacpp-router-models.ini"
        ubatch_size = 512
        """
        try toml.write(to: tmpURL, atomically: true, encoding: .utf8)

        try await settings.load(from: tmpURL)

        XCTAssertEqual(settings.slotAssignments[.execute], "llamacpp:qwen3-coder-local")
        XCTAssertEqual(settings.slotAssignments[.reason], "deepseek")
        XCTAssertEqual(settings.slotAssignments[.orchestrate], "deepseek")
        XCTAssertEqual(settings.slotAssignments[.vision], "llamacpp:qwen3-vl-local")
        XCTAssertEqual(settings.llamaCppRuntime.serverPath, "/opt/homebrew/bin/llama-server")
        XCTAssertEqual(settings.llamaCppRuntime.ubatchSize, 512)
    }

    func test_load_missingFileUsesDefaults() async throws {
        let absent = URL(fileURLWithPath: "/tmp/no-such-file-\(UUID().uuidString).toml")
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

    func test_watchedConfigReloadDebouncesRapidEvents() async throws {
        try "max_tokens = 111\n".write(to: tmpURL, atomically: true, encoding: .utf8)
        settings.scheduleWatchedConfigReload(for: tmpURL, delay: .milliseconds(120))

        try "max_tokens = 222\n".write(to: tmpURL, atomically: true, encoding: .utf8)
        settings.scheduleWatchedConfigReload(for: tmpURL, delay: .milliseconds(120))

        try await Task.sleep(for: .milliseconds(260))

        XCTAssertEqual(settings.maxTokens, 222)
    }

    // MARK: - SettingsProposal

    func test_propose_approvedByUser() async {
        settings.proposalApprover = { _ in true }
        let accepted = await settings.propose(.setMaxTokens(2048))
        XCTAssertTrue(accepted)
        XCTAssertEqual(settings.maxTokens, 2048)
    }

    func test_propose_deniedByUser() async {
        settings.proposalApprover = { _ in false }
        let originalMax = settings.maxTokens
        let accepted = await settings.propose(.setMaxTokens(9999))
        XCTAssertFalse(accepted)
        XCTAssertEqual(settings.maxTokens, originalMax)
    }

    func test_propose_standingInstructions() async {
        settings.proposalApprover = { _ in true }
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

    func test_resetToDefaultsPreservingConnectorSecrets_resetsExtendedSettings() {
        settings.ragRerank = true
        settings.kagEnabled = true
        settings.kagXcalibreURL = "http://xcalibre.local"
        settings.loraEnabled = true
        settings.promptCompressionEnabled = true
        settings.slotAssignments[.execute] = "lmstudio:phi-4"
        settings.xcalibreToken = "keep-me"

        settings.resetToDefaultsPreservingConnectorSecrets()

        XCTAssertFalse(settings.ragRerank)
        XCTAssertFalse(settings.kagEnabled)
        XCTAssertEqual(settings.kagXcalibreURL, "")
        XCTAssertFalse(settings.loraEnabled)
        XCTAssertFalse(settings.promptCompressionEnabled)
        XCTAssertTrue(settings.slotAssignments.isEmpty)
        XCTAssertEqual(settings.xcalibreToken, "keep-me")
    }
}
