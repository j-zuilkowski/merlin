# Phase 118a — LoRATrainer Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 117b complete: OutcomeRecord prompt/response fields in place.

Current state: No LoRA training infrastructure exists. Phase 118b introduces LoRATrainer,
which exports training data as MLX-LM JSONL and shells out to `python -m mlx_lm.lora`.

New surface introduced in phase 118b:
  - `LoRATrainer` — actor
  - `LoRATrainer.exportJSONL(_ records: [OutcomeRecord], to url: URL) throws`
      Writes one JSON object per line:
      {"messages":[{"role":"user","content":"<prompt>"},{"role":"assistant","content":"<response>"}]}
      Skips records with empty prompt or response (defensive: exportTrainingData already filters,
      but LoRATrainer is independently safe).
  - `LoRATrainer.train(records:baseModel:adapterOutputPath:iterations:) async -> LoRATrainingResult`
      Writes JSONL to a temp file, then runs:
      python -m mlx_lm.lora --model <baseModel> --train --data <jsonlPath>
          --adapter-path <adapterOutputPath> --iters <iterations> --batch-size 1
      Returns LoRATrainingResult.
  - `LoRATrainingResult: Sendable` — sampleCount, adapterPath, success, errorMessage

TDD coverage:
  File 1 — LoRATrainerTests: JSONL line format correct; empty records skipped; train()
            constructs correct shell arguments; empty dataset returns success=false without
            running shell; LoRATrainingResult fields populated correctly.

---

## Write to: MerlinTests/Unit/LoRATrainerTests.swift

```swift
import XCTest
@testable import Merlin

final class LoRATrainerTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("merlin-118-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - JSONL export format

    func testExportJSONLWritesCorrectFormat() throws {
        // BUILD FAILED until 118b adds LoRATrainer
        let trainer = LoRATrainer()
        let records = [
            makeRecord(prompt: "Fix the null pointer", response: "Add a guard statement."),
            makeRecord(prompt: "Add tests for login", response: "I've added 3 XCTest cases."),
        ]
        let url = tempDir.appendingPathComponent("train.jsonl")
        try trainer.exportJSONL(records, to: url)

        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 2, "One JSONL line per record")

        // Verify first line is valid JSON with expected structure
        let firstLine = String(lines[0])
        let data = firstLine.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let messages = json["messages"] as! [[String: String]]
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"], "user")
        XCTAssertEqual(messages[0]["content"], "Fix the null pointer")
        XCTAssertEqual(messages[1]["role"], "assistant")
        XCTAssertEqual(messages[1]["content"], "Add a guard statement.")
    }

    func testExportJSONLSkipsRecordsWithEmptyText() throws {
        let trainer = LoRATrainer()
        let records = [
            makeRecord(prompt: "Good prompt", response: "Good response"),
            makeRecord(prompt: "", response: ""),          // should be skipped
            makeRecord(prompt: "Another prompt", response: ""),  // should be skipped
        ]
        let url = tempDir.appendingPathComponent("train2.jsonl")
        try trainer.exportJSONL(records, to: url)

        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 1, "Only records with both prompt and response written")
    }

    // MARK: - train() with empty dataset

    func testTrainReturnsFailureForEmptyDataset() async {
        let trainer = LoRATrainer()
        let result = await trainer.train(
            records: [],
            baseModel: "mlx-community/Qwen2.5-Coder-7B-Instruct-4bit",
            adapterOutputPath: tempDir.path,
            iterations: 100
        )
        XCTAssertFalse(result.success, "Training with zero records must return success = false")
        XCTAssertEqual(result.sampleCount, 0)
        XCTAssertNotNil(result.errorMessage)
    }

    // MARK: - train() shell command construction

    func testTrainBuildsCorrectShellCommand() async {
        // Use a stub ShellRunner that captures the command without executing it.
        let capturer = CapturingShellRunner()
        let trainer = LoRATrainer(shellRunner: capturer)
        let records = [makeRecord(prompt: "p", response: "r")]

        _ = await trainer.train(
            records: records,
            baseModel: "mlx-community/Qwen2.5-Coder-7B-Instruct-4bit",
            adapterOutputPath: "/tmp/adapter",
            iterations: 50
        )

        XCTAssertTrue(capturer.lastCommand?.contains("mlx_lm.lora") ?? false,
                      "Shell command must invoke mlx_lm.lora")
        XCTAssertTrue(capturer.lastCommand?.contains("--train") ?? false)
        XCTAssertTrue(capturer.lastCommand?.contains("mlx-community/Qwen2.5-Coder-7B-Instruct-4bit") ?? false)
        XCTAssertTrue(capturer.lastCommand?.contains("--adapter-path") ?? false)
        XCTAssertTrue(capturer.lastCommand?.contains("--iters 50") ?? false)
    }

    // MARK: - LoRATrainingResult fields

    func testTrainingResultFieldsPopulated() async {
        let capturer = CapturingShellRunner(exitCode: 0)
        let trainer = LoRATrainer(shellRunner: capturer)
        let records = [
            makeRecord(prompt: "Prompt 1", response: "Response 1"),
            makeRecord(prompt: "Prompt 2", response: "Response 2"),
        ]
        let result = await trainer.train(
            records: records,
            baseModel: "mlx-community/Qwen2.5-Coder-7B-Instruct-4bit",
            adapterOutputPath: "/tmp/adapter",
            iterations: 10
        )
        XCTAssertEqual(result.sampleCount, 2)
        XCTAssertEqual(result.adapterPath, "/tmp/adapter")
        XCTAssertTrue(result.success)
        XCTAssertNil(result.errorMessage)
    }
}

// MARK: - Helpers

private func makeRecord(prompt: String, response: String) -> OutcomeRecord {
    OutcomeRecord(
        modelID: "test-model",
        taskType: DomainTaskType(domainID: "software", name: "code-edit", displayName: "Code Edit"),
        score: 0.9,
        addendumHash: "00000000",
        timestamp: Date(),
        prompt: prompt,
        response: response
    )
}

/// Captures the shell command passed to it without actually executing anything.
final class CapturingShellRunner: ShellRunnerProtocol, @unchecked Sendable {
    var lastCommand: String?
    private let exitCode: Int32

    init(exitCode: Int32 = 0) { self.exitCode = exitCode }

    func run(command: String) async -> ShellRunResult {
        lastCommand = command
        return ShellRunResult(exitCode: exitCode, output: "", errorOutput: "")
    }
}
```

---

## Verify
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD FAILED — `LoRATrainer`, `LoRATrainingResult`, `ShellRunnerProtocol`,
`ShellRunResult`, `CapturingShellRunner` not defined.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/LoRATrainerTests.swift
git commit -m "Phase 118a — LoRATrainerTests (failing)"
```
