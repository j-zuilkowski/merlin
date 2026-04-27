import Foundation

extension ToolDefinition {
    static let spawnAgent = ToolDefinition(
        function: .init(
            name: "spawn_agent",
            description: "Spawn a subagent to run a task in parallel.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "agent": JSONSchema(
                        type: "string",
                        description: "Agent name. Built-ins: 'explorer', 'worker', 'default'. Custom agents from ~/.merlin/agents/."
                    ),
                    "prompt": JSONSchema(
                        type: "string",
                        description: "The task prompt to send to the subagent."
                    )
                ],
                required: ["agent", "prompt"]
            )
        )
    )
}
