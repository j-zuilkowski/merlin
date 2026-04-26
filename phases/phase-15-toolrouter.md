# Phase 15 — ToolRouter

Context: HANDOFF.md. All tool implementations exist. AuthGate exists.

## Write to: Merlin/Engine/ToolRouter.swift

```swift
import Foundation

@MainActor
final class ToolRouter {
    private let authGate: AuthGate
    // Injected tool implementations
    init(authGate: AuthGate)

    // Dispatches tool calls returned by LLM
    // Parallel: all calls dispatched concurrently via TaskGroup
    // Returns results in original index order
    func dispatch(_ calls: [ToolCall]) async -> [ToolResult]

    // Registers a handler for a named tool
    func register(name: String, handler: @escaping (String) async throws -> String)
}
```

Dispatch logic per call:
1. Extract the primary argument string from the JSON arguments for AuthGate:
```swift
func primaryArgument(from json: String) -> String {
    guard let data = json.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return json }
    // Priority: path > command > bundle_id > first string value
    for key in ["path", "command", "bundle_id", "src", "udid"] {
        if let v = obj[key] as? String { return v }
    }
    return obj.values.compactMap { $0 as? String }.first ?? json
}
```
Pass `(tool: call.function.name, argument: primaryArgument(from: call.function.arguments))` to `authGate.check`.
2. If `.deny` → return `ToolResult(toolCallId: call.id, content: "Denied by user", isError: true)`
3. If `.allow` → execute registered handler with `call.function.arguments`
4. If handler throws → call `authGate.reportFailure`, retry once after 1s, then return error result
5. Return `ToolResult(toolCallId: call.id, content: output, isError: false)`

## Write to: MerlinTests/Unit/ToolRouterTests.swift

```swift
final class ToolRouterTests: XCTestCase {

    func testDispatchesInParallel() async {
        let memory = AuthMemory(storePath: "/dev/null")
        memory.addAllowPattern(tool: "echo_a", pattern: "*")
        memory.addAllowPattern(tool: "echo_b", pattern: "*")
        let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())
        let router = ToolRouter(authGate: gate)
        router.register(name: "echo_a") { _ in "A" }
        router.register(name: "echo_b") { _ in "B" }

        let calls = [
            ToolCall(id: "1", type: "function", function: FunctionCall(name: "echo_a", arguments: "{}")),
            ToolCall(id: "2", type: "function", function: FunctionCall(name: "echo_b", arguments: "{}")),
        ]
        let results = await router.dispatch(calls)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].content, "A")
        XCTAssertEqual(results[1].content, "B")
    }

    func testDeniedToolReturnsError() async {
        let memory = AuthMemory(storePath: "/dev/null")
        memory.addDenyPattern(tool: "bad_tool", pattern: "*")
        let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())
        let router = ToolRouter(authGate: gate)
        let calls = [ToolCall(id: "x", type: "function",
                              function: FunctionCall(name: "bad_tool", arguments: "{}"))]
        let results = await router.dispatch(calls)
        XCTAssertTrue(results[0].isError)
    }
}
```

## Acceptance
- [ ] `swift test --filter ToolRouterTests` — both pass
- [ ] `swift build` — zero errors
