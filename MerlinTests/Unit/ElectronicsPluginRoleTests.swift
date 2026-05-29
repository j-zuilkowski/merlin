import XCTest
@testable import Merlin

final class ElectronicsPluginRoleTests: XCTestCase {
    func testElectronicsPluginDeclaresAnalogCriticRole() {
        let plugin = ElectronicsRuntimePlugin()

        let role = plugin.metadata.roles.first { $0.id == "electronics.analog_critic" }

        XCTAssertEqual(role?.displayName, "Analog Critic")
        XCTAssertEqual(role?.pluginID, "electronics")
        XCTAssertEqual(role?.scope, "electronics")
        XCTAssertEqual(role?.fallbackSlot, .reason)
        XCTAssertEqual(role?.requiredCapabilities, ["structured_output", "long_context"])
        XCTAssertEqual(role?.recommendedModels, ["analog-specialist", "deepseek-r1-70b"])
        XCTAssertEqual(role?.isRequired, false)
    }

    func testAnalogCriticRoleIsNotDeclaredByMerlinCore() {
        let registry = DynamicRoleRegistry()

        XCTAssertFalse(registry.availableRoleIDs.contains("electronics.analog_critic"))
        XCTAssertNil(registry.definition(for: "electronics.analog_critic"))
    }

    func testLoadingAndUnloadingElectronicsMetadataControlsAnalogCriticRole() {
        var registry = DynamicRoleRegistry()
        let plugin = ElectronicsRuntimePlugin()

        registry.register(metadata: plugin.metadata)
        XCTAssertNotNil(registry.definition(for: "electronics.analog_critic"))

        registry.unregisterPluginRoles(pluginID: plugin.metadata.id)
        XCTAssertNil(registry.definition(for: "electronics.analog_critic"))
    }
}
