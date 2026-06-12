import XCTest
@testable import WebSearchPlugin

final class ManifestTests: XCTestCase {
    func testManifestDeclaresSettingsCapabilitiesAndRoutes() throws {
        let manifest = PluginManifest.manifest()

        XCTAssertEqual(manifest["id"] as? String, "web-search")
        XCTAssertEqual(manifest["trust_tier"] as? String, "tier2")
        let settings = try XCTUnwrap(manifest["settings_schema"] as? [String: Any])
        XCTAssertEqual(settings["namespace"] as? String, "plugin.web_search")

        let routes = try XCTUnwrap(manifest["tool_routes"] as? [[String: Any]])
        XCTAssertTrue(routes.contains { route in
            route["tool_name"] as? String == "web_search"
                && route["stable_alias"] as? String == "web_search"
                && route["required_permission_scope"] as? String == "externalSideEffect"
        })
    }

    func testManifestTextIsJSON() throws {
        let data = Data(PluginManifest.manifestText().utf8)
        let object = try XCTUnwrap(JSON.dictionary(from: data))
        XCTAssertEqual(object["display_name"] as? String, "Web Search")
    }
}
