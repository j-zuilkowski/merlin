import Foundation
import XCTest
@testable import Merlin

final class ContextBudgetResolverTests: XCTestCase {

    private final class StubProvider: LLMProvider, @unchecked Sendable {
        let id: String
        let baseURL = URL(fileURLWithPath: "/tmp")

        init(id: String) {
            self.id = id
        }

        func complete(request: CompletionRequest)
            async throws -> AsyncThrowingStream<CompletionChunk, Error> {
            AsyncThrowingStream { $0.finish() }
        }
    }

    /// An in-memory `ContextBudgetStore` that records the last write - lets a test
    /// assert both that persistence happened and that the persisted value is reused.
    private actor RecordingBudgetStore: ContextBudgetStore {
        private var byID: [String: Int]
        private(set) var lastPersisted: Int?

        init(seed: [String: Int] = [:]) { byID = seed }

        func persistedContextTokens(for providerID: String) async -> Int? {
            byID[providerID]
        }
        func persist(contextTokens: Int, for providerID: String) async {
            byID[providerID] = contextTokens
            lastPersisted = contextTokens
        }
    }

    func testDiscoveredContextYieldsContextMinusReservedOutput() async {
        let resolver = ContextBudgetResolver(reservedOutputTokens: 4_096,
                                             conservativeContextTokens: 32_000,
                                             source: { _ in 8_192 })
        let budget = await resolver.usableInputTokens(for: StubProvider(id: "lmstudio:m"))
        XCTAssertEqual(budget, 8_192 - 4_096)
    }

    func testNilDiscoveryAndEmptyStoreFallsBackToConservative() async {
        let resolver = ContextBudgetResolver(reservedOutputTokens: 4_096,
                                             conservativeContextTokens: 32_000,
                                             source: { _ in nil })
        let budget = await resolver.usableInputTokens(for: StubProvider(id: "lmstudio:m"))
        XCTAssertEqual(budget, 32_000 - 4_096)
    }

    func testPersistedStoreUsedWhenLiveDiscoveryReturnsNil() async {
        // OpenAI/Anthropic/DeepSeek cannot be queried live (source -> nil); a value
        // previously persisted to providers.json must be honoured over the fallback.
        let store = RecordingBudgetStore(seed: ["deepseek": 16_384])
        let resolver = ContextBudgetResolver(reservedOutputTokens: 4_096,
                                             conservativeContextTokens: 32_000,
                                             store: store,
                                             source: { _ in nil })
        let budget = await resolver.usableInputTokens(for: StubProvider(id: "deepseek"))
        XCTAssertEqual(budget, 16_384 - 4_096,
            "a persisted context window must win over the conservative fallback")
    }

    func testBudgetNeverGoesBelowAFloor() async {
        // A tiny reported context must not produce a zero or negative budget.
        let resolver = ContextBudgetResolver(reservedOutputTokens: 4_096,
                                             conservativeContextTokens: 32_000,
                                             source: { _ in 2_048 })
        let budget = await resolver.usableInputTokens(for: StubProvider(id: "lmstudio:tiny"))
        XCTAssertGreaterThan(budget, 0,
            "a small context window must still yield a positive usable budget")
    }

    func testSourceIsConsultedOncePerProviderWithinTTL() async {
        let counter = CallCounter()
        let resolver = ContextBudgetResolver(
            ttl: 300,
            source: { _ in await counter.bump(); return 8_192 })
        let p = StubProvider(id: "lmstudio:m")
        _ = await resolver.usableInputTokens(for: p)
        _ = await resolver.usableInputTokens(for: p)
        let calls = await counter.value
        XCTAssertEqual(calls, 1, "discovery must be cached within the TTL")
    }

    func testRecordedLimitIsPersistedAndSurvivesCacheExpiry() async {
        // ttl 0 -> the in-memory cache is always stale, so the second resolve must come
        // from the persisted store. This is the conservative-start / learn-from-400 /
        // never-pay-it-twice path for commercial providers.
        let store = RecordingBudgetStore()
        let resolver = ContextBudgetResolver(reservedOutputTokens: 4_096,
                                             conservativeContextTokens: 32_000,
                                             ttl: 0,
                                             store: store,
                                             source: { _ in nil })
        let p = StubProvider(id: "deepseek")

        let before = await resolver.usableInputTokens(for: p)
        XCTAssertEqual(before, 32_000 - 4_096, "starts conservative before any 400")

        await resolver.recordObservedLimit(contextTokens: 8_192, for: p)

        let persisted = await store.lastPersisted
        XCTAssertEqual(persisted, 8_192,
            "a learned limit must be written through to the durable store")

        let after = await resolver.usableInputTokens(for: p)
        XCTAssertEqual(after, 8_192 - 4_096,
            "after learning, the resolved budget must reflect the persisted window")
    }

    func testLiveDiscoveryIsWrittenThroughToTheStore() async {
        // A queryable runner's live value should also be persisted, so providers.json
        // stays current and a later launch has a good starting point.
        let store = RecordingBudgetStore()
        let resolver = ContextBudgetResolver(reservedOutputTokens: 4_096,
                                             store: store,
                                             source: { _ in 8_192 })
        _ = await resolver.usableInputTokens(for: StubProvider(id: "lmstudio:m"))
        let persisted = await store.lastPersisted
        XCTAssertEqual(persisted, 8_192,
            "a live-discovered context window must be written through to the store")
    }

    private actor CallCounter {
        private(set) var value = 0
        func bump() { value += 1 }
    }
}
