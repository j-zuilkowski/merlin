import XCTest
@testable import Merlin

final class DynamicPluginRoleTests: XCTestCase {
    func testBuiltInRolesRemainAvailableByDefault() {
        let registry = DynamicRoleRegistry()

        XCTAssertEqual(registry.availableRoleIDs, ["execute", "reason", "orchestrate", "vision"])
        XCTAssertEqual(registry.definition(for: "execute")?.displayName, "Execute")
        XCTAssertEqual(registry.definition(for: "reason")?.fallbackSlot, .reason)
        XCTAssertEqual(registry.definition(for: "orchestrate")?.fallbackSlot, .reason)
        XCTAssertEqual(registry.definition(for: "vision")?.fallbackSlot, .vision)
    }

    func testPluginRolesAppearOnlyWhilePluginIsLoaded() {
        var registry = DynamicRoleRegistry()
        let role = PluginRoleDefinition(
            id: "electronics.analog_critic",
            displayName: "Analog Critic",
            pluginID: "electronics",
            scope: "electronics",
            fallbackSlot: .reason,
            requiredCapabilities: ["structured_output", "long_context"],
            recommendedModels: ["analog-specialist", "deepseek-r1-70b"],
            isRequired: false
        )

        XCTAssertNil(registry.definition(for: "electronics.analog_critic"))

        registry.register(pluginRoles: [role], pluginID: "electronics")

        XCTAssertEqual(registry.definition(for: "electronics.analog_critic"), role)
        XCTAssertTrue(registry.availableRoleIDs.contains("electronics.analog_critic"))

        registry.unregisterPluginRoles(pluginID: "electronics")

        XCTAssertNil(registry.definition(for: "electronics.analog_critic"))
        XCTAssertFalse(registry.availableRoleIDs.contains("electronics.analog_critic"))
    }

    func testOptionalPluginRoleFallsBackToReasonWhenUnassigned() {
        var registry = DynamicRoleRegistry()
        registry.register(pluginRoles: [
            PluginRoleDefinition(
                id: "electronics.analog_critic",
                displayName: "Analog Critic",
                pluginID: "electronics",
                scope: "electronics",
                fallbackSlot: .reason,
                requiredCapabilities: [],
                recommendedModels: [],
                isRequired: false
            )
        ], pluginID: "electronics")

        let resolution = registry.resolve(
            roleID: "electronics.analog_critic",
            assignments: [:],
            requireAssignment: false
        )

        XCTAssertEqual(resolution, .slot(.reason))
    }

    func testRequiredPluginRoleWithoutAssignmentBlocks() {
        var registry = DynamicRoleRegistry()
        registry.register(pluginRoles: [
            PluginRoleDefinition(
                id: "electronics.layout_critic",
                displayName: "Layout Critic",
                pluginID: "electronics",
                scope: "electronics",
                fallbackSlot: .reason,
                requiredCapabilities: [],
                recommendedModels: [],
                isRequired: true
            )
        ], pluginID: "electronics")

        let resolution = registry.resolve(
            roleID: "electronics.layout_critic",
            assignments: [:],
            requireAssignment: true
        )

        XCTAssertEqual(resolution, .blocked(code: "ROLE_UNASSIGNED"))
    }
}
