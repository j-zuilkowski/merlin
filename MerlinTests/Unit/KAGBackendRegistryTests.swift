import XCTest
@testable import Merlin

@MainActor
final class KAGBackendRegistryTests: XCTestCase {

    func test_default_plugin_is_null() {
        // Fresh registry (not shared — create a new instance for isolation).
        let registry = KAGBackendRegistry()
        XCTAssertTrue(registry.current is NullKAGPlugin)
    }

    func test_register_replaces_current() {
        let registry = KAGBackendRegistry()
        let mock = MockKAGPlugin()
        registry.register(mock)
        XCTAssertTrue(registry.current is MockKAGPlugin)
    }

    func test_register_second_time_replaces_again() {
        let registry = KAGBackendRegistry()
        registry.register(MockKAGPlugin())
        registry.register(NullKAGPlugin())
        XCTAssertTrue(registry.current is NullKAGPlugin)
    }
}

// MARK: - Test double
final class MockKAGPlugin: KAGBackendPlugin, @unchecked Sendable {
    var writtenTriples: [KAGTriple] = []

    func writeTriples(_ triples: [KAGTriple]) async throws {
        writtenTriples.append(contentsOf: triples)
    }

    func traverse(anchor: String, hops: Int, domainId: String?) async throws -> [KAGTriple] {
        return []
    }
}
