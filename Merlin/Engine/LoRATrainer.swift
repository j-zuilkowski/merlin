import Foundation

// MARK: - ShellRunnerProtocol

/// Abstraction over running a shell command. Real implementation uses Process;
/// tests inject CapturingShellRunner to avoid executing system commands.
protocol ShellRunnerProtocol: Sendable {
    func run(command: String) async -> ShellRunResult
}

struct ShellRunResult: Sendable {
    let exitCode: Int32
    let output: String
    let errorOutput: String
}

// MARK: - ProcessShellRunner

/// Production implementation: runs the command via /bin/zsh and captures stdout/stderr.
struct ProcessShellRunner: ShellRunnerProtocol {
    func run(command: String) async -> ShellRunResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                continuation.resume(returning: ShellRunResult(
                    exitCode: -1, output: "", errorOutput: error.localizedDescription
                ))
                return
            }

            let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(),
                             encoding: .utf8) ?? ""
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                             encoding: .utf8) ?? ""
            continuation.resume(returning: ShellRunResult(
                exitCode: process.terminationStatus, output: out, errorOutput: err
            ))
        }
    }
}

// MARK: - LoRATrainingResult

struct LoRATrainingResult: Sendable {
    let sampleCount: Int
    let adapterPath: String
    let success: Bool
    let errorMessage: String?
}

// MARK: - LoRATrainer

/// Exports session OutcomeRecords as MLX-LM training JSONL and shells out to
/// `python -m mlx_lm.lora` to fine-tune a local model on the M4 Mac.
///
/// Training only fires when loraEnabled + loraAutoTrain + sample threshold met.
/// The trained adapter is saved to loraAdapterPath; when loraAutoLoad is true,
/// AgenticEngine routes the execute slot to the mlx_lm.server running that adapter.
actor LoRATrainer {

    private let shellRunner: any ShellRunnerProtocol

    init(shellRunner: any ShellRunnerProtocol = ProcessShellRunner()) {
        self.shellRunner = shellRunner
    }

    // MARK: - JSONL Export

    /// Writes one line per record in MLX-LM chat format:
    /// {"messages":[{"role":"user","content":"..."},{"role":"assistant","content":"..."}]}
    /// Records with empty prompt or response are silently skipped.
    nonisolated func exportJSONL(_ records: [OutcomeRecord], to url: URL) throws {
        let validRecords = records.filter { !$0.prompt.isEmpty && !$0.response.isEmpty }
        let lines = try validRecords.map { record -> String in
            let messages: [[String: String]] = [
                ["role": "user",      "content": record.prompt],
                ["role": "assistant", "content": record.response],
            ]
            let obj: [String: Any] = ["messages": messages]
            let data = try JSONSerialization.data(withJSONObject: obj)
            return String(data: data, encoding: .utf8) ?? ""
        }
        let content = lines.joined(separator: "\n")
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Training

    /// Exports records to a temp JSONL file and runs `python -m mlx_lm.lora --train`.
    /// Returns immediately with success=false if there are no valid training samples.
    func train(
        records: [OutcomeRecord],
        baseModel: String,
        adapterOutputPath: String,
        iterations: Int = 100
    ) async -> LoRATrainingResult {
        let valid = records.filter { !$0.prompt.isEmpty && !$0.response.isEmpty }
        guard !valid.isEmpty else {
            return LoRATrainingResult(
                sampleCount: 0,
                adapterPath: adapterOutputPath,
                success: false,
                errorMessage: "No training samples with non-empty prompt and response."
            )
        }

        // Write JSONL to a temporary file
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("merlin-lora-train-\(UUID().uuidString).jsonl")
        do {
            try exportJSONL(valid, to: tempURL)
        } catch {
            return LoRATrainingResult(
                sampleCount: valid.count,
                adapterPath: adapterOutputPath,
                success: false,
                errorMessage: "JSONL export failed: \(error.localizedDescription)"
            )
        }
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Ensure adapter output directory exists
        try? FileManager.default.createDirectory(
            atPath: adapterOutputPath,
            withIntermediateDirectories: true
        )

        let command = [
            "python -m mlx_lm.lora",
            "--model \"\(baseModel)\"",
            "--train",
            "--data \"\(tempURL.path)\"",
            "--adapter-path \"\(adapterOutputPath)\"",
            "--iters \(iterations)",
            "--batch-size 1",
        ].joined(separator: " ")

        let result = await shellRunner.run(command: command)

        if result.exitCode == 0 {
            return LoRATrainingResult(
                sampleCount: valid.count,
                adapterPath: adapterOutputPath,
                success: true,
                errorMessage: nil
            )
        } else {
            let msg = result.errorOutput.isEmpty ? result.output : result.errorOutput
            return LoRATrainingResult(
                sampleCount: valid.count,
                adapterPath: adapterOutputPath,
                success: false,
                errorMessage: msg.isEmpty ? "mlx_lm.lora exited with code \(result.exitCode)" : msg
            )
        }
    }
}
