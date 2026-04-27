import XCTest
@testable import Merlin

@MainActor
final class ReasoningEffortTests: XCTestCase {

    // MARK: - ProviderRegistry.reasoningEffortSupported

    func test_anthropicClaude3Opus_supported() {
        XCTAssertTrue(ProviderRegistry.reasoningEffortSupported(for: "claude-3-opus-20240229"))
    }

    func test_claude3Haiku_notSupported() {
        XCTAssertFalse(ProviderRegistry.reasoningEffortSupported(for: "claude-3-haiku-20240307"))
    }

    func test_lmStudio_qwq_supported() {
        XCTAssertTrue(ProviderRegistry.reasoningEffortSupported(for: "qwq-32b-preview"))
    }

    func test_lmStudio_deepseekR1_supported() {
        XCTAssertTrue(ProviderRegistry.reasoningEffortSupported(for: "deepseek-r1-distill-qwen-7b"))
    }

    func test_lmStudio_r1Prefix_supported() {
        XCTAssertTrue(ProviderRegistry.reasoningEffortSupported(for: "r1-lite-preview"))
    }

    func test_lmStudio_llama_notSupported() {
        XCTAssertFalse(ProviderRegistry.reasoningEffortSupported(for: "llama-3.2-3b"))
    }

    func test_override_enablesUnsupportedModel() {
        let overrides = ["llama-3.2-3b": true]
        XCTAssertTrue(ProviderRegistry.reasoningEffortSupported(for: "llama-3.2-3b", overrides: overrides))
    }

    func test_override_disablesSupportedModel() {
        let overrides = ["qwq-32b-preview": false]
        XCTAssertFalse(ProviderRegistry.reasoningEffortSupported(for: "qwq-32b-preview", overrides: overrides))
    }

    func test_unknownModel_notSupported() {
        XCTAssertFalse(ProviderRegistry.reasoningEffortSupported(for: "some-unknown-model-v1"))
    }

    // MARK: - ReasoningEffort enum

    func test_reasoningEffort_allCases() {
        XCTAssertEqual(ReasoningEffort.allCases.count, 3)
    }

    func test_reasoningEffort_apiValues() {
        XCTAssertEqual(ReasoningEffort.high.apiValue, "high")
        XCTAssertEqual(ReasoningEffort.medium.apiValue, "medium")
        XCTAssertEqual(ReasoningEffort.low.apiValue, "low")
    }

    // MARK: - ContextUsageTracker

    func test_contextUsage_initialZero() {
        let tracker = ContextUsageTracker(contextWindowSize: 200_000)
        XCTAssertEqual(tracker.usedTokens, 0)
        XCTAssertEqual(tracker.percentUsed, 0.0, accuracy: 0.001)
    }

    func test_contextUsage_update() {
        let tracker = ContextUsageTracker(contextWindowSize: 100_000)
        tracker.update(usedTokens: 50_000)
        XCTAssertEqual(tracker.usedTokens, 50_000)
        XCTAssertEqual(tracker.percentUsed, 0.5, accuracy: 0.001)
    }

    func test_contextUsage_statusString() {
        let tracker = ContextUsageTracker(contextWindowSize: 200_000)
        tracker.update(usedTokens: 40_000)
        let status = tracker.statusString
        XCTAssertTrue(status.contains("40,000") || status.contains("40000"))
        XCTAssertTrue(status.contains("20%") || status.contains("20.0%"))
    }
}
