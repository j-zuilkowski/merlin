import XCTest
@testable import Merlin

final class ToolRegistryTests: XCTestCase {

    private var registry: ToolRegistry!

    override func setUp() async throws {
        registry = ToolRegistry()
    }

    // MARK: - Basic registration

    func test_register_addsToAll() async {
        let tool = ToolDefinition.stub(name: "test_tool")
        await registry.register(tool)
        let all = await registry.all()
        XCTAssertTrue(all.contains(where: { $0.function.name == "test_tool" }))
    }

    func test_contains_trueAfterRegister() async {
        let tool = ToolDefinition.stub(name: "my_tool")
        await registry.register(tool)
        let found = await registry.contains(named: "my_tool")
        XCTAssertTrue(found)
    }

    func test_contains_falseWhenAbsent() async {
        let found = await registry.contains(named: "ghost_tool")
        XCTAssertFalse(found)
    }

    // MARK: - Unregistration

    func test_unregister_removesFromAll() async {
        let tool = ToolDefinition.stub(name: "removable")
        await registry.register(tool)
        await registry.unregister(named: "removable")
        let found = await registry.contains(named: "removable")
        XCTAssertFalse(found)
    }

    func test_unregister_noopWhenAbsent() async {
        await registry.unregister(named: "nonexistent")
        let all = await registry.all()
        XCTAssertTrue(all.isEmpty)
    }

    // MARK: - Idempotent registration

    func test_register_duplicateIsIdempotent() async {
        let tool = ToolDefinition.stub(name: "dupe")
        await registry.register(tool)
        await registry.register(tool)
        let all = await registry.all()
        let count = all.filter { $0.function.name == "dupe" }.count
        XCTAssertEqual(count, 1)
    }

    // MARK: - Count

    func test_all_emptyInitially() async {
        let all = await registry.all()
        XCTAssertTrue(all.isEmpty)
    }

    func test_all_countMatchesRegistrations() async {
        await registry.register(ToolDefinition.stub(name: "a"))
        await registry.register(ToolDefinition.stub(name: "b"))
        await registry.register(ToolDefinition.stub(name: "c"))
        let all = await registry.all()
        XCTAssertEqual(all.count, 3)
    }

    // MARK: - registerBuiltins

    func test_registerBuiltins_populates40Tools() async {
        await registry.registerBuiltins()
        let all = await registry.all()
        XCTAssertEqual(all.count, 40)
    }

    func test_registerBuiltins_idempotent() async {
        await registry.registerBuiltins()
        await registry.registerBuiltins()
        let all = await registry.all()
        XCTAssertEqual(all.count, 40)
    }

    // MARK: - Reset (test helper)

    func test_reset_clearsAll() async {
        await registry.registerBuiltins()
        await registry.reset()
        let all = await registry.all()
        XCTAssertTrue(all.isEmpty)
    }

    // MARK: - Ordering

    func test_all_preservesRegistrationOrder() async {
        let names = ["z_tool", "a_tool", "m_tool"]
        for name in names {
            await registry.register(ToolDefinition.stub(name: name))
        }
        let result = await registry.all().map { $0.function.name }
        XCTAssertEqual(result, names)
    }

    // MARK: - Concurrent safety

    func test_concurrentRegister_noDataRace() async {
        let registry = registry!
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<50 {
                group.addTask {
                    await registry.register(ToolDefinition.stub(name: "tool_\(index)"))
                }
            }
        }
        let all = await registry.all()
        XCTAssertEqual(all.count, 50)
    }
}

extension ToolDefinition {
    static func stub(name: String) -> ToolDefinition {
        ToolDefinition(
            type: "function",
            function: .init(
                name: name,
                description: "stub \(name)",
                parameters: .init(type: "object", properties: [:], required: [])
            )
        )
    }
}
