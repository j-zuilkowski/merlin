import XCTest

final class FullBatteryCleanupTests: XCTestCase {
    private let scriptPath = "docs/e2e/2026-05-26-merlin-full-gui/run-live-full.sh"

    func testCapabilityFixturesSeedProjectConfigAfterArchiveExtraction() throws {
        let source = try repoFile("MerlinE2ETests/CapabilityScenarioTests.swift")

        XCTAssertTrue(source.contains("seedProjectConfigIfNeeded"))
        XCTAssertTrue(source.contains("initializeFixtureGitRepository"))
        XCTAssertTrue(source.contains("case \"swift-gui-buggy\":"))
        XCTAssertTrue(source.contains("adapter = \"swift-xcode\""))
        XCTAssertTrue(source.contains("case \"rust-buggy\":"))
        XCTAssertTrue(source.contains("adapter = \"rust-cargo\""))
    }

    func testRunnerTracksOwnedProcessesAndTrapsInterrupts() throws {
        let script = try repoFile(scriptPath)

        XCTAssertTrue(script.contains("RUNNER_OWNED_PIDS=()"))
        XCTAssertTrue(script.contains("record_owned_pid"))
        XCTAssertTrue(script.contains("trap cleanup EXIT INT TERM"))
    }

    func testRunnerClosesConflictingTestAppsBeforeXcodebuild() throws {
        let script = try repoFile(scriptPath)

        XCTAssertTrue(script.contains("stop_test_apps()"))
        XCTAssertTrue(script.contains("pkill -TERM -x Merlin"))
        let backup = try XCTUnwrap(script.range(of: "\nbackup_user_config\n")?.upperBound)
        let afterBackup = String(script[backup...])
        let stop = try XCTUnwrap(afterBackup.range(of: "\nstop_test_apps\n")?.lowerBound)
        let core = try XCTUnwrap(afterBackup.range(of: "\"core unit suite\"")?.lowerBound)

        XCTAssertLessThan(afterBackup.distance(from: afterBackup.startIndex, to: stop),
                          afterBackup.distance(from: afterBackup.startIndex, to: core))
    }

    func testConfigBackupsLiveOutsideRetainedEvidence() throws {
        let script = try repoFile(scriptPath)

        XCTAssertTrue(script.contains("BACKUP_DIR=\"$(mktemp -d"))
        XCTAssertFalse(script.contains("CONFIG_BAK=\"$RUN_DIR/config.toml.bak\""))
        XCTAssertFalse(script.contains("PROVIDERS_BAK=\"$RUN_DIR/providers.json.bak\""))
    }

    func testDryRunCleanupAndScreenshotHygieneAreDocumented() throws {
        let script = try repoFile(scriptPath)

        XCTAssertTrue(script.contains("--dry-run-cleanup"))
        XCTAssertTrue(script.contains("remove_red_battery_artifacts"))
        XCTAssertTrue(script.contains("cleanup summary:"))
    }

    func testRunnerAggregatesFailuresAndExitsNonZeroUnlessGreen() throws {
        let script = try repoFile(scriptPath)

        XCTAssertTrue(script.contains("FAILURES=()"))
        XCTAssertTrue(script.contains("--self-test-failure-aggregation"))
        XCTAssertTrue(script.contains("run_step_timeout"))
        XCTAssertTrue(script.contains("capture_timeout_diagnostics"))
        XCTAssertTrue(script.contains("FULL_BATTERY_GREEN=1"))
        XCTAssertTrue(script.contains("exit 1"))
        XCTAssertFalse(script.contains("xcodebuild-live-S1.log\" 2>&1 || true"))
        XCTAssertFalse(script.contains("xcodebuild-live-S2.log\" 2>&1 || true"))
    }

    func testRunnerSamplesXCTestHostOnTimeout() throws {
        let script = try repoFile(scriptPath)

        XCTAssertTrue(script.contains("capture_timeout_diagnostics()"))
        XCTAssertTrue(script.contains("Build/Products/Debug/Merlin.app"))
        XCTAssertFalse(script.contains("awk '/Build\\\\/Products"))
        XCTAssertTrue(script.contains("sample \"$app_pid\" 3"))
        XCTAssertTrue(script.contains("_prepareTestConfigurationAndIDESession"))
        XCTAssertTrue(script.contains("Timeout diagnostics:"))
    }

    func testRunnerFailureAggregationSelfTestExitsNonZero() throws {
        let result = try runScript([repoRoot().appendingPathComponent(scriptPath).path, "--self-test-failure-aggregation"])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("FAIL self test fail"), result.output)
        XCTAssertTrue(result.output.contains("Failures: 1"), result.output)
    }

    func testRunnerDryRunCleanupExecutesSuccessfully() throws {
        let result = try runScript([repoRoot().appendingPathComponent(scriptPath).path, "--dry-run-cleanup"])

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("cleanup summary:"), result.output)
    }

    func testRunnerCoversExpectedFullBatterySurfaces() throws {
        let script = try repoFile(scriptPath)

        XCTAssertTrue(script.contains("MerlinTests"))
        XCTAssertTrue(script.contains("MerlinUITests"))
        XCTAssertTrue(script.contains("-scheme MerlinTests-Live"))
        XCTAssertFalse(script.contains("-scheme MerlinUITests"))
        XCTAssertTrue(script.contains("DeepSeekProviderLiveTests"))
        XCTAssertTrue(script.contains("AgenticLoopE2ETests"))
        XCTAssertTrue(script.contains("testS1SwiftGUIDebugCycle"))
        XCTAssertTrue(script.contains("testS2RustDebugCycle"))
        XCTAssertTrue(script.contains("testS4RAGGrounding"))
        XCTAssertTrue(script.contains("testS5LoRAPipeline"))
        XCTAssertTrue(script.contains("testS6Electronics"))
        XCTAssertTrue(script.contains("testS6SchematicOCR"))
        XCTAssertTrue(script.contains("docs/local-provider-configs/smoke-test.sh"))
    }

    func testRunnerTimesOutLiveAgenticProviderLoop() throws {
        let script = try repoFile(scriptPath)

        XCTAssertTrue(script.contains("run_xcode_step_timeout \"deepseek agentic loop live\""))
        XCTAssertFalse(script.contains("run_shell_step \"deepseek agentic loop live\""))
    }

    func testRunnerTimesOutTopLevelXcodebuildStages() throws {
        let script = try repoFile(scriptPath)

        for stage in [
            "core unit suite",
            "full gui suite",
            "focused visual gui suite",
            "deepseek provider live"
        ] {
            XCTAssertTrue(script.contains("run_xcode_step_timeout \"\(stage)\""),
                          "missing reset-aware timeout for \(stage)")
            XCTAssertFalse(script.contains("run_shell_step \"\(stage)\""),
                           "unbounded xcodebuild stage still present for \(stage)")
        }
    }

    func testRunnerPinsXcodeDestinationAndUsesRealisticBudgets() throws {
        let script = try repoFile(scriptPath)

        XCTAssertTrue(script.contains("XCODE_DESTINATION=\"${XCODE_DESTINATION:-platform=macOS,arch=arm64}\""))
        XCTAssertTrue(script.contains("XCODE_PREFLIGHT_TIMEOUT=\"${XCODE_PREFLIGHT_TIMEOUT:-300}\""))
        XCTAssertTrue(script.contains("XCODE_CORE_TIMEOUT=\"${XCODE_CORE_TIMEOUT:-1800}\""))
        XCTAssertTrue(script.contains("run_xcode_step_timeout()"))
        XCTAssertTrue(script.contains("stop_test_apps"))
        XCTAssertFalse(script.contains("-destination 'platform=macOS'"))
    }

    func testRunnerOwnsEveryLocalProviderLifecycle() throws {
        let script = try repoFile(scriptPath)

        for provider in ["jan", "localai", "mistralrs", "vllm"] {
            XCTAssertTrue(script.contains("start_\(provider)"), "missing start function for \(provider)")
            XCTAssertFalse(script.contains("no runner-owned \(provider)"), "provider \(provider) still has no-lifecycle skip")
        }
        XCTAssertFalse(script.contains("skip_step \"local provider jan"))
        XCTAssertFalse(script.contains("skip_step \"local provider localai"))
        XCTAssertFalse(script.contains("skip_step \"local provider mistralrs"))
        XCTAssertFalse(script.contains("skip_step \"local provider vllm"))
        XCTAssertTrue(script.contains("stop_port_listener 1337"))
        XCTAssertTrue(script.contains("stop_ollama"))
        XCTAssertTrue(script.contains("VLLM_METAL_MEMORY_FRACTION"))
    }

    func testRunnerClassifiesMistralRsProviderModelGapAsUnsupported() throws {
        let script = try repoFile(scriptPath)
        let smoke = try repoFile("docs/local-provider-configs/smoke-test.sh")

        XCTAssertTrue(script.contains("run_shell_step_allow_unsupported \"local provider mistralrs smoke\""))
        XCTAssertTrue(script.contains("SMOKE_ALLOW_PROVIDER_MODEL_GAP=1"))
        XCTAssertTrue(script.contains("provider/model unsupported"))
        XCTAssertTrue(smoke.contains("UNSUPPORTED_PROVIDER_MODEL_GAP"))
        XCTAssertTrue(smoke.contains("return 77"))
        XCTAssertTrue(smoke.contains("provider_status=$?"))
        XCTAssertTrue(smoke.contains("HTTP 500 from provider/model combination"))
    }

    func testRunnerDoesNotLeaveDeadXcalibreConfiguredForLaterScenarios() throws {
        let script = try repoFile(scriptPath)

        XCTAssertTrue(script.contains("write_lmstudio_config false"))
        XCTAssertFalse(script.contains("xcalibre_url = \"http://127.0.0.1:8094\""))
    }

    func testRunnerWritesLoopbackProviderEndpointForLMStudio() throws {
        let script = try repoFile(scriptPath)

        XCTAssertTrue(script.contains("\"baseURL\": \"http://127.0.0.1:1234/v1\""))
        XCTAssertTrue(script.contains("\"activeProviderID\": \"lmstudio\""))
        XCTAssertFalse(script.contains("\"baseURL\": \"http://localhost:1234/v1\""))
    }

    func testRunnerStartsLMStudioBeforeS1AndS2Capabilities() throws {
        let script = try repoFile(scriptPath)

        let smokes = try XCTUnwrap(script.range(of: "\nrun_local_provider_smokes\n")?.lowerBound)
        let beforeSmokes = String(script[..<smokes])
        let start = try XCTUnwrap(beforeSmokes.range(of: "if start_lmstudio_pair; then")?.lowerBound)
        let s1 = try XCTUnwrap(script.range(of: "capability S1 swift gui")?.lowerBound)
        let s2 = try XCTUnwrap(script.range(of: "capability S2 rust")?.lowerBound)
        let startOffset = beforeSmokes.distance(from: beforeSmokes.startIndex, to: start)
        let s1Offset = script.distance(from: script.startIndex, to: s1)
        let s2Offset = script.distance(from: script.startIndex, to: s2)
        let smokesOffset = script.distance(from: script.startIndex, to: smokes)

        XCTAssertLessThan(startOffset, s1Offset)
        XCTAssertLessThan(s1Offset, s2Offset)
        XCTAssertLessThan(s2Offset, smokesOffset)
        XCTAssertTrue(script.contains("lmstudio pair startup for S1/S2 live scenarios"))
    }

    func testRunnerClearsLMStudioModelsBeforeEachOwnedPairLoad() throws {
        let script = try repoFile(scriptPath)
        let functionStart = try XCTUnwrap(script.range(of: "start_lmstudio_pair() {")?.lowerBound)
        let afterStart = String(script[functionStart...])
        let functionEnd = try XCTUnwrap(afterStart.range(of: "\n}\n\nstart_ollama")?.lowerBound)
        let function = String(afterStart[..<functionEnd])

        let unload = try XCTUnwrap(function.range(of: "lms unload --all")?.lowerBound)
        let loadText = try XCTUnwrap(function.range(of: "lms load \"$LMSTUDIO_TEXT_MODEL\"")?.lowerBound)
        let loadVision = try XCTUnwrap(function.range(of: "lms load \"$LMSTUDIO_VISION_MODEL\"")?.lowerBound)

        XCTAssertLessThan(function.distance(from: function.startIndex, to: unload),
                          function.distance(from: function.startIndex, to: loadText))
        XCTAssertLessThan(function.distance(from: function.startIndex, to: loadText),
                          function.distance(from: function.startIndex, to: loadVision))
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
        final class ProcessBox: @unchecked Sendable {
            let process: Process
            init(_ process: Process) { self.process = process }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = arguments

        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("merlin-runner-test-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logURL)
        defer {
            try? logHandle.close()
            try? FileManager.default.removeItem(at: logURL)
        }
        process.standardOutput = logHandle
        process.standardError = logHandle

        try process.run()
        let box = ProcessBox(process)
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            box.process.waitUntilExit()
            done.signal()
        }

        var timedOut = false
        if done.wait(timeout: .now() + 30) == .timedOut {
            timedOut = true
            Self.terminateChildren(of: process.processIdentifier)
            process.terminate()
            if done.wait(timeout: .now() + 3) == .timedOut {
                Self.killChildren(of: process.processIdentifier)
                kill(process.processIdentifier, SIGKILL)
                _ = done.wait(timeout: .now() + 3)
            }
        }

        try? logHandle.synchronize()
        let data = (try? Data(contentsOf: logURL)) ?? Data()
        let output = String(data: data, encoding: .utf8) ?? ""
        if timedOut {
            return (124, output + "\nTimed out waiting for script: \(arguments.joined(separator: " "))")
        }
        return (process.terminationStatus, output)
    }

    private static func terminateChildren(of pid: pid_t) {
        _ = runPkill(signal: "TERM", parentPID: pid)
    }

    private static func killChildren(of pid: pid_t) {
        _ = runPkill(signal: "KILL", parentPID: pid)
    }

    private static func runPkill(signal: String, parentPID: pid_t) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process.arguments = ["-\(signal)", "-P", String(parentPID)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
