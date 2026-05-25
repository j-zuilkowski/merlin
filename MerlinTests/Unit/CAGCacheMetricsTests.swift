import XCTest
@testable import Merlin

final class CAGCacheMetricsTests: XCTestCase {

    func testUsageComputesHitRate() {
        let usage = CAGCacheUsage(readTokens: 80, creationTokens: 20, uncachedInputTokens: 100)
        XCTAssertEqual(usage.hitRate, 80.0 / 200.0, accuracy: 0.0001)
    }

    func testMetricsStoreAggregatesProviderUsage() async {
        let store = CAGCacheMetricsStore()

        await store.record(.init(readTokens: 50, creationTokens: 10, uncachedInputTokens: 40), providerID: "anthropic")
        await store.record(.init(readTokens: 30, creationTokens: 5, uncachedInputTokens: 15), providerID: "anthropic")

        let snapshot = await store.snapshot(providerID: "anthropic")
        XCTAssertEqual(snapshot.readTokens, 80)
        XCTAssertEqual(snapshot.creationTokens, 15)
        XCTAssertEqual(snapshot.uncachedInputTokens, 55)
    }

    func testMetricsStoreResetsProviderUsage() async {
        let store = CAGCacheMetricsStore()

        await store.record(.init(readTokens: 10, creationTokens: 2, uncachedInputTokens: 8), providerID: "anthropic")
        await store.reset(providerID: "anthropic")

        let snapshot = await store.snapshot(providerID: "anthropic")
        XCTAssertEqual(snapshot, .init(readTokens: 0, creationTokens: 0, uncachedInputTokens: 0))
    }

    func testMetricsStoreSnapshotsAndResetsAllProviders() async {
        let store = CAGCacheMetricsStore()

        await store.record(.init(readTokens: 10, creationTokens: 1, uncachedInputTokens: 2), providerID: "anthropic")
        await store.record(.init(readTokens: 20, creationTokens: 3, uncachedInputTokens: 4), providerID: "deepseek")

        let snapshot = await store.snapshotAll()
        XCTAssertEqual(snapshot["anthropic"]?.readTokens, 10)
        XCTAssertEqual(snapshot["deepseek"]?.readTokens, 20)

        await store.resetAll()
        let afterReset = await store.snapshotAll()
        XCTAssertTrue(afterReset.isEmpty)
    }
}
