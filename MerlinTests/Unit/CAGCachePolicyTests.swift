import XCTest
@testable import Merlin

@MainActor
final class CAGCachePolicyTests: XCTestCase {

    func testDefaultPolicyIsDisabled() {
        XCTAssertFalse(CAGCachePolicy.disabled.isCacheable)
    }

    func testEphemeralPolicyIsCacheable() {
        XCTAssertTrue(CAGCachePolicy.ephemeral.isCacheable)
    }

    func testStableToolOrderingSortsByName() {
        let tools = [
            ToolDefinition(function: .init(
                name: "zeta_tool",
                description: "z",
                parameters: JSONSchema(type: "object")
            )),
            ToolDefinition(function: .init(
                name: "alpha_tool",
                description: "a",
                parameters: JSONSchema(type: "object")
            )),
            ToolDefinition(function: .init(
                name: "beta_tool",
                description: "b",
                parameters: JSONSchema(type: "object")
            )),
        ]

        let ordered = CAGToolOrdering.stable(tools)
        XCTAssertEqual(ordered.map { $0.function.name }, ["alpha_tool", "beta_tool", "zeta_tool"])
    }

    func testStableToolOrderingDeduplicatesByName() {
        let tools = [
            ToolDefinition(function: .init(name: "dup", description: "first", parameters: JSONSchema(type: "object"))),
            ToolDefinition(function: .init(name: "alpha", description: "a", parameters: JSONSchema(type: "object"))),
            ToolDefinition(function: .init(name: "dup", description: "second", parameters: JSONSchema(type: "object"))),
        ]

        let ordered = CAGToolOrdering.stable(tools)
        XCTAssertEqual(ordered.map { $0.function.name }, ["alpha", "dup"])
    }

    func testStableToolOrderingKeepsFirstDefinitionForDuplicateName() {
        let first = ToolDefinition(function: .init(
            name: "dup",
            description: "first-description",
            parameters: JSONSchema(type: "object")
        ))
        let second = ToolDefinition(function: .init(
            name: "dup",
            description: "second-description",
            parameters: JSONSchema(type: "object")
        ))

        let ordered = CAGToolOrdering.stable([second, first])
        XCTAssertEqual(ordered.count, 1)
        XCTAssertEqual(ordered.first?.function.description, "second-description")
    }

    func testHotRAGAndKAGTextIsNotPartOfStablePrefix() {
        let engine = makeEngine(provider: MockProvider(response: "ok"))
        let stablePrefix = engine.buildStablePrefix()

        XCTAssertFalse(stablePrefix.contains("[Relevant passages from your library]"))
        XCTAssertFalse(stablePrefix.contains("## Knowledge Graph"))
    }
}
