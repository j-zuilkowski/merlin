//  AgenticEngineKAGWiringTests.swift
//  Verifies that AgenticEngine calls KAGEngine.scheduleExtraction after each
//  assistant turn when kagEnabled = true, and skips it when kagEnabled = false.
//
//  scheduleExtraction() sets self.pendingTask synchronously (before the 2-second
//  idle delay), so we can assert it is non-nil immediately after the turn.

import XCTest
@testable import Merlin

@MainActor
final class AgenticEngineKAGWiringTests: XCTestCase {

    private var settingsURL: URL!

    override func setUp() async throws {
        settingsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("kag-wiring-\(UUID().uuidString).toml")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: settingsURL)
        // Reset kagEnabled to default so other tests are not polluted.
        AppSettings.shared.kagEnabled = false
    }

    // MARK: - Enabled

    func test_scheduleExtraction_called_when_kagEnabled() async throws {
        AppSettings.shared.kagEnabled = true

        let provider = MockProvider(chunks: [
            .init(delta: .init(content: "Swift is a compiled language."), finishReason: nil),
            .init(delta: .init(content: nil), finishReason: "stop"),
        ])

        let kag = KAGEngine(registry: KAGBackendRegistry())
        let engine = makeEngine(provider: provider, kagEngine: kag)

        for await _ in engine.send(userMessage: "Tell me about Swift.") {}

        XCTAssertNotNil(kag.pendingTask,
            "pendingTask must be non-nil — scheduleExtraction() was not called")

        kag.pendingTask?.cancel()
    }

    // MARK: - Disabled

    func test_scheduleExtraction_skipped_when_kagDisabled() async throws {
        AppSettings.shared.kagEnabled = false

        let provider = MockProvider(chunks: [
            .init(delta: .init(content: "hello"), finishReason: nil),
            .init(delta: .init(content: nil), finishReason: "stop"),
        ])

        let kag = KAGEngine(registry: KAGBackendRegistry())
        let engine = makeEngine(provider: provider, kagEngine: kag)

        for await _ in engine.send(userMessage: "hi") {}

        XCTAssertNil(kag.pendingTask,
            "pendingTask must be nil — scheduleExtraction() must not fire when kagEnabled=false")
    }

    // MARK: - Empty response

    func test_scheduleExtraction_skipped_for_empty_response() async throws {
        AppSettings.shared.kagEnabled = true

        let provider = MockProvider(chunks: [
            .init(delta: .init(content: nil), finishReason: "stop"),
        ])

        let kag = KAGEngine(registry: KAGBackendRegistry())
        let engine = makeEngine(provider: provider, kagEngine: kag)

        for await _ in engine.send(userMessage: "hi") {}

        XCTAssertNil(kag.pendingTask,
            "pendingTask must be nil — scheduleExtraction() must not fire for empty response text")
    }
}
