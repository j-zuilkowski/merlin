import XCTest
@testable import Merlin

final class CriticEngineTests: XCTestCase {

    private let taskType = DomainTaskType(
        domainID: "software", name: "code_generation", displayName: "Code Generation"
    )

    // MARK: - Stage 1

    func testStage1PassWhenCommandSucceeds() async {
        let backend = StubVerificationBackend(exitCode: 0)
        let engine = CriticEngine(
            verificationBackend: backend,
            reasonProvider: nil,
            shellRunner: StubShellRunner(exitCode: 0)
        )
        let result = await engine.evaluate(taskType: taskType, output: "let x = 1", context: [])
        XCTAssertEqual(result, .pass)
    }

    func testStage1FailWhenCommandFails() async {
        let backend = StubVerificationBackend(exitCode: 0)
        let engine = CriticEngine(
            verificationBackend: backend,
            reasonProvider: nil,
            shellRunner: StubShellRunner(exitCode: 1, output: "error: build failed")
        )
        let result = await engine.evaluate(taskType: taskType, output: "let x = }", context: [])
        if case .fail(let reason) = result {
            XCTAssertTrue(reason.contains("build failed") || reason.contains("Compile"))
        } else {
            XCTFail("Expected .fail, got \(result)")
        }
    }

    func testStage1FailureReasonPreservesNamedFailingXcodeTestsAfterVerboseBuildOutput() async {
        let output = String(repeating: "MkDir /DerivedData/TaskBoard/Build/Products/Debug\n", count: 20)
            + """
            Failing tests:
                TaskStoreTests.testDeleteRemovesTheTaskAtThatIndex()
                TaskStoreTests.testSummaryCountsDoneOnly()
            ** TEST FAILED **
            """
        let backend = StubVerificationBackend(exitCode: 0)
        let engine = CriticEngine(
            verificationBackend: backend,
            reasonProvider: nil,
            shellRunner: StubShellRunner(exitCode: 1, output: output)
        )

        let result = await engine.evaluate(taskType: taskType, output: "done", context: [])

        guard case .fail(let reason) = result else {
            return XCTFail("Expected .fail, got \(result)")
        }
        XCTAssertTrue(reason.contains("testDeleteRemovesTheTaskAtThatIndex"), reason)
        XCTAssertTrue(reason.contains("testSummaryCountsDoneOnly"), reason)
        XCTAssertTrue(reason.contains("TEST FAILED"), reason)
    }

    func testStage1SkippedWhenNullBackend() async {
        let engine = CriticEngine(
            verificationBackend: NullVerificationBackend(),
            reasonProvider: nil,
            shellRunner: StubShellRunner(exitCode: 0)
        )
        // NullVerificationBackend → Stage 1 skipped, no reason provider → Stage 2 skipped
        let result = await engine.evaluate(taskType: taskType, output: "anything", context: [])
        XCTAssertEqual(result, .skipped)
    }

    // MARK: - Auto-detected project build verification

    func testAutoDetectsCargoProject() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("critic-cargo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "[package]\nname=\"x\"".write(
            to: dir.appendingPathComponent("Cargo.toml"), atomically: true, encoding: .utf8)

        let engine = CriticEngine(
            verificationBackend: NullVerificationBackend(),
            reasonProvider: nil,
            shellRunner: StubShellRunner(exitCode: 0),
            projectPath: dir.path)
        let debugging = DomainTaskType(
            domainID: "software", name: "debugging", displayName: "Debugging")
        let commands = await engine.autoDetectedProjectCommands(for: debugging)
        XCTAssertEqual(commands.count, 2, "cargo project → build + test commands")
        XCTAssertTrue(commands.allSatisfy { $0.command.contains("cargo") })
        XCTAssertTrue(commands.contains { $0.command.contains("cargo test") })
        XCTAssertTrue(commands.allSatisfy { $0.command.contains("$HOME/.cargo/bin") },
                      "Cargo verification must work under the app/test host's stripped PATH")
    }

    func testAutoDetectSkipsNonCodeTaskType() async {
        let engine = CriticEngine(
            verificationBackend: NullVerificationBackend(),
            reasonProvider: nil,
            shellRunner: StubShellRunner(exitCode: 0),
            projectPath: NSTemporaryDirectory())
        let explanation = DomainTaskType(
            domainID: "software", name: "explanation", displayName: "Explanation")
        let commands = await engine.autoDetectedProjectCommands(for: explanation)
        XCTAssertTrue(commands.isEmpty, "explanation tasks must not trigger a build check")
    }

    func testAutoDetectEmptyWithoutProjectPath() async {
        let engine = CriticEngine(
            verificationBackend: NullVerificationBackend(),
            reasonProvider: nil,
            shellRunner: StubShellRunner(exitCode: 0))
        let commands = await engine.autoDetectedProjectCommands(for: taskType)
        XCTAssertTrue(commands.isEmpty)
    }

    func testFirstSchemeParsesXcodebuildListJSON() {
        let projectJSON = #"{"project":{"name":"TaskBoard","schemes":["TaskBoard","Tests"]}}"#
        XCTAssertEqual(
            CriticEngine.firstScheme(fromXcodebuildListJSON: projectJSON), "TaskBoard")
        let workspaceJSON = #"{"workspace":{"name":"W","schemes":["AppScheme"]}}"#
        XCTAssertEqual(
            CriticEngine.firstScheme(fromXcodebuildListJSON: workspaceJSON), "AppScheme")
        XCTAssertNil(CriticEngine.firstScheme(fromXcodebuildListJSON: "not json"))
    }

    func testAutoDetectsXcodeProject() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("critic-xcode-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("App.xcodeproj"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let engine = CriticEngine(
            verificationBackend: NullVerificationBackend(),
            reasonProvider: nil,
            shellRunner: StubShellRunner(
                exitCode: 0, output: #"{"project":{"schemes":["App"]}}"#),
            projectPath: dir.path)
        let debugging = DomainTaskType(
            domainID: "software", name: "debugging", displayName: "Debugging")
        let commands = await engine.autoDetectedProjectCommands(for: debugging)
        XCTAssertEqual(commands.count, 1)
        XCTAssertTrue(commands[0].command.contains("xcodebuild test -scheme 'App'"))
    }

    func testHasAutoDetectableProjectDetectsBuildSystems() throws {
        let fm = FileManager.default
        func tempDir(marker: String?, isDirMarker: Bool = false) throws -> String {
            let dir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("critic-detect-\(UUID().uuidString)")
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            if let marker {
                let m = dir.appendingPathComponent(marker)
                if isDirMarker {
                    try fm.createDirectory(at: m, withIntermediateDirectories: true)
                } else {
                    try "x".write(to: m, atomically: true, encoding: .utf8)
                }
            }
            return dir.path
        }
        let cargo = try tempDir(marker: "Cargo.toml")
        let spm = try tempDir(marker: "Package.swift")
        let xcode = try tempDir(marker: "App.xcodeproj", isDirMarker: true)
        let plain = try tempDir(marker: "README.md")
        defer { for d in [cargo, spm, xcode, plain] { try? fm.removeItem(atPath: d) } }

        XCTAssertTrue(CriticEngine.hasAutoDetectableProject(at: cargo))
        XCTAssertTrue(CriticEngine.hasAutoDetectableProject(at: spm))
        XCTAssertTrue(CriticEngine.hasAutoDetectableProject(at: xcode))
        XCTAssertFalse(CriticEngine.hasAutoDetectableProject(at: plain),
                       "a directory with no build system must not be detected")
        XCTAssertFalse(CriticEngine.hasAutoDetectableProject(at: nil))
        XCTAssertFalse(CriticEngine.hasAutoDetectableProject(at: ""))
    }

    // MARK: - Stage 2 graceful degradation

    func testStage2SkippedWhenReasonProviderNil() async {
        // Stage 1 passes, Stage 2 has no provider → .pass (not skipped, stage 1 covered it)
        let backend = StubVerificationBackend(exitCode: 0)
        let engine = CriticEngine(
            verificationBackend: backend,
            reasonProvider: nil,
            shellRunner: StubShellRunner(exitCode: 0)
        )
        let result = await engine.evaluate(taskType: taskType, output: "good code", context: [])
        // Stage 1 passed, no Stage 2 → overall pass
        XCTAssertEqual(result, .pass)
    }

    func testStage2EvaluatesWhenReasonProviderAvailable() async {
        let backend = NullVerificationBackend()
        let mockReason = MockReasonProvider(response: "PASS: looks correct")
        let engine = CriticEngine(
            verificationBackend: backend,
            reasonProvider: mockReason,
            shellRunner: StubShellRunner(exitCode: 0)
        )
        let result = await engine.evaluate(taskType: taskType, output: "correct output", context: [])
        XCTAssertEqual(result, .pass)
    }

    func testStage2FailWhenReasonProviderIndicatesFailure() async {
        let backend = NullVerificationBackend()
        let mockReason = MockReasonProvider(response: "FAIL: the output is missing error handling")
        let engine = CriticEngine(
            verificationBackend: backend,
            reasonProvider: mockReason,
            shellRunner: StubShellRunner(exitCode: 0)
        )
        let result = await engine.evaluate(taskType: taskType, output: "incomplete output", context: [])
        if case .fail(let reason) = result {
            XCTAssertTrue(reason.contains("missing error handling"))
        } else {
            XCTFail("Expected .fail, got \(result)")
        }
    }
}

// MARK: - Test stubs

private struct StubVerificationBackend: VerificationBackend {
    var exitCode: Int
    func verificationCommands(for taskType: DomainTaskType) -> [VerificationCommand]? {
        [VerificationCommand(label: "Compile", command: "echo test",
                             passCondition: .exitCode(exitCode))]
    }
}

private struct StubShellRunner: ShellRunning {
    var exitCode: Int
    var output: String = ""
    func run(_ command: String) async -> (exitCode: Int, output: String) {
        (exitCode, output)
    }
}

private final class MockReasonProvider: LLMProvider {
    let id = "mock-reason"
    let response: String
    init(response: String) { self.response = response }
    let baseURL = URL(string: "http://localhost") ?? URL(fileURLWithPath: "/")
    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error> {
        let text = response
        return AsyncThrowingStream { continuation in
            continuation.yield(CompletionChunk(
                delta: ChunkDelta(content: text, toolCalls: nil, thinkingContent: nil),
                finishReason: "stop"
            ))
            continuation.finish()
        }
    }
}
