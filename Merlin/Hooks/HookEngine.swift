// HookEngine — runs user-configured shell scripts at agent lifecycle events.
//
// Events: PreToolUse (allow/deny), PostToolUse (rewrite result),
//         UserPromptSubmit (rewrite prompt), Stop (continue looping).
//
// Each hook is launched as a /bin/sh child process. JSON is passed on stdin;
// the hook's stdout is parsed as JSON. Non-zero exit → failure (deny / no change).
// The engine is recreated from AppSettings on each turn so changes take effect
// without restarting.
//
// See: Developer Manual § "Hook System"
import Foundation

actor HookEngine {
    private var hooks: [HookConfig]

    init(hooks: [HookConfig] = []) {
        self.hooks = hooks
    }

    func configure(hooks: [HookConfig]) {
        self.hooks = hooks
    }

    func runPreToolUse(toolName: String, input: [String: String]) async -> HookDecision {
        let relevant = hooks.filter { $0.event == "PreToolUse" && $0.enabled }
        guard relevant.isEmpty == false else {
            return .allow
        }

        var payload: [String: Any] = ["tool": toolName]
        if input.isEmpty == false {
            payload["input"] = input
        }

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return .deny(reason: "HookEngine: failed to encode payload")
        }

        for hook in relevant {
            let output = await runScript(hook.command, stdin: json)
            guard output.exitCode == 0 else {
                return .deny(reason: "HookEngine: hook failed")
            }
            guard let response = parseJSON(output.stdout),
                  let decision = response["decision"] as? String else {
                return .deny(reason: "HookEngine: invalid hook output")
            }
            if decision == "deny" {
                let reason = response["reason"] as? String ?? "Denied by hook"
                return .deny(reason: reason)
            }
        }

        return .allow
    }

    func runPostToolUse(toolName: String, result: String) async -> String? {
        let relevant = hooks.filter { $0.event == "PostToolUse" && $0.enabled }
        guard relevant.isEmpty == false else {
            return nil
        }

        let payload: [String: Any] = ["tool": toolName, "result": result]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }

        var current = result
        var changed = false

        for hook in relevant {
            let output = await runScript(hook.command, stdin: json)
            guard output.exitCode == 0 else {
                continue
            }
            guard output.stdout.isEmpty == false else {
                continue
            }
            current = output.stdout
            changed = true
        }

        return changed ? current : nil
    }

    func runUserPromptSubmit(prompt: String) async -> String? {
        let relevant = hooks.filter { $0.event == "UserPromptSubmit" && $0.enabled }
        guard relevant.isEmpty == false else {
            return nil
        }

        var current = prompt
        var changed = false

        for hook in relevant {
            let output = await runScript(hook.command, stdin: current)
            guard output.exitCode == 0 else {
                continue
            }
            guard output.stdout.isEmpty == false else {
                continue
            }
            current = output.stdout
            changed = true
        }

        return changed ? current : nil
    }

    func runStop() async -> Bool {
        let relevant = hooks.filter { $0.event == "Stop" && $0.enabled }
        guard relevant.isEmpty == false else {
            return false
        }

        for hook in relevant {
            let output = await runScript(hook.command, stdin: "")
            guard output.exitCode == 0,
                  output.stdout.isEmpty == false,
                  let response = parseJSON(output.stdout),
                  let proceed = response["proceed"] as? Bool else {
                continue
            }
            if proceed == true {
                return true
            }
        }

        return false
    }

    private func runScript(_ command: String, stdin: String) async -> (stdout: String, exitCode: Int) {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]

            let stdinPipe = Pipe()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
            } catch {
                continuation.resume(returning: ("", 1))
                return
            }

            if stdin.isEmpty == false, let data = stdin.data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(data)
            }
            stdinPipe.fileHandleForWriting.closeFile()

            process.waitUntilExit()

            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            continuation.resume(returning: (stdout, Int(process.terminationStatus)))
        }
    }

    private func parseJSON(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
