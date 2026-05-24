import Foundation

extension ToolDefinition {
    static let spawnAgent = ToolDefinition(
        function: .init(
            name: "spawn_agent",
            description: "Spawn a subagent for an INDEPENDENT exploration or research "
                + "subtask whose result you read back as one summary. Do NOT use it to "
                + "parallelize a sequential build/test/fix/verify cycle or a step-by-step "
                + "pipeline — perform those directly with your own tools, because a "
                + "subagent's tool calls and progress do not feed back into your loop. "
                + "When in doubt, do the work yourself.",
            parameters: JSONSchema(
                type: "object",
                properties: [
                    "agent": JSONSchema(
                        type: "string",
                        description: "Agent name. Built-ins: 'explorer', 'worker', 'default'. Custom agents from ~/.merlin/agents/."
                    ),
                    "task": JSONSchema(
                        type: "string",
                        description: "The task prompt to send to the subagent."
                    ),
                    "prompt": JSONSchema(
                        type: "string",
                        description: "Deprecated alias for task."
                    ),
                    "context": JSONSchema(
                        type: "string",
                        description: "Optional extra context to prepend before the task."
                    ),
                ],
                required: ["agent", "task"]
            )
        )
    )
}
