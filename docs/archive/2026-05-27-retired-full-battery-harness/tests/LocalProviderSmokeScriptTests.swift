import XCTest

final class LocalProviderSmokeScriptTests: XCTestCase {
    func testLlamaCppSmokeUsesExplicitTextAndVisionEnvironmentOverrides() throws {
        let script = try repoFile("docs/local-provider-configs/smoke-test.sh")

        XCTAssertTrue(script.contains("LLAMACPP_TEXT_MODEL"))
        XCTAssertTrue(script.contains("LLAMACPP_VISION_MODEL"))
        XCTAssertTrue(script.contains("/tmp/smoke-vision-model-id-"))
    }

    func testLlamaCppSmokeRejectsRouterDefaultModel() throws {
        let script = try repoFile("docs/local-provider-configs/smoke-test.sh")

        XCTAssertTrue(script.contains("model_id = 'default'"))
        XCTAssertTrue(script.contains("llama.cpp router catalog exposed only default"))
        XCTAssertFalse(script.contains("echo \"$first_model\" > /tmp/smoke-model-id-\"$id\"\n    return 0\n}\n\nprobe_completion"))
    }

    func testLlamaCppSmokeRecordsExactModelIDsForEveryAxis() throws {
        let script = try repoFile("docs/local-provider-configs/smoke-test.sh")

        XCTAssertTrue(script.contains("text model:"))
        XCTAssertTrue(script.contains("vision model:"))
        XCTAssertTrue(script.contains("probe_vision"))
    }

    func testSmokeScriptExercisesSupportedVisionProviderAxes() throws {
        let script = try repoFile("docs/local-provider-configs/smoke-test.sh")

        XCTAssertTrue(script.contains("JAN_VISION_MODEL"))
        XCTAssertTrue(script.contains("LOCALAI_VISION_MODEL"))
        XCTAssertTrue(script.contains("SMOKE_ONLY_VISION"))
        XCTAssertTrue(script.contains("SMOKE_REQUIRE_VISION"))
    }

    func testSmokeScriptPropagatesProviderFailuresToExitStatus() throws {
        let script = try repoFile("docs/local-provider-configs/smoke-test.sh")

        XCTAssertTrue(script.contains("local failed=0"))
        XCTAssertTrue(script.contains("local unsupported=0"))
        XCTAssertTrue(script.contains("local provider_status=$?"))
        XCTAssertTrue(script.contains("if [ \"$provider_status\" -eq 77 ]"))
        XCTAssertTrue(script.contains("return 77"))
        XCTAssertTrue(script.contains("return 1"))
        XCTAssertTrue(script.contains("return 0"))
    }

    func testUnknownProviderExitsNonZero() throws {
        let root = repoRoot()
        let result = try runScript([
            root.appendingPathComponent("docs/local-provider-configs/smoke-test.sh").path,
            "definitely-not-a-provider"
        ])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("Unknown provider: definitely-not-a-provider"), result.output)
        XCTAssertTrue(result.output.contains("definitely-not-a-provider"), result.output)
    }

    private func repoFile(_ path: String) throws -> String {
        let root = repoRoot()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func runScript(_ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }
}
