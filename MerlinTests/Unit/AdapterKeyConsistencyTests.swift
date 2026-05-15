import XCTest
@testable import Merlin

final class AdapterKeyConsistencyTests: XCTestCase {

    func testSeedAdaptersAreKeyedByAdapterKey() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }

        try await AdapterRegistry.installSeedAdapters(into: dir.path)

        let registry = AdapterRegistry()
        try await registry.loadFromDirectory(dir.path)

        // The seed files are swift-xcode.toml and rust-cargo.toml. ProjectConfig.adapter
        // identifies the adapter by that filename stem, so lookup must succeed by key.
        let swift = try await registry.adapter(for: "swift-xcode")
        XCTAssertEqual(swift.language, "swift",
                       "Adapter registered under key 'swift-xcode' describes the swift language")

        let rust = try await registry.adapter(for: "rust-cargo")
        XCTAssertEqual(rust.language, "rust",
                       "Adapter registered under key 'rust-cargo' describes the rust language")
    }
}
