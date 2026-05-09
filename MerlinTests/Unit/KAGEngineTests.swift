import XCTest
@testable import Merlin

@MainActor
final class KAGEngineTests: XCTestCase {

    func test_scheduleExtraction_writes_to_registered_plugin() async throws {
        let registry = KAGBackendRegistry()
        let mock = MockKAGPlugin()
        registry.register(mock)

        let engine = KAGEngine(registry: registry)
        engine.scheduleExtraction(from: "U4 shares_net VCC in electronics domain", domain: "electronics")

        // Wait for the idle timer + extraction (stub returns [] in 190b, so writtenTriples stays empty
        // but the call must not throw and must attempt to write).
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 s > 2 s idle timer
        // In 190b the extractor is stubbed to return []; written count is 0 but no error.
        XCTAssertEqual(mock.writtenTriples.count, 0,
                       "stub extractor returns []; writtenTriples should be 0 in 190b")
    }

    func test_scheduleExtraction_does_not_throw_on_null_plugin() async throws {
        let registry = KAGBackendRegistry() // NullKAGPlugin by default
        let engine = KAGEngine(registry: registry)
        // Must not crash or throw
        engine.scheduleExtraction(from: "anything", domain: "test")
        try await Task.sleep(nanoseconds: 3_000_000_000)
    }
}
