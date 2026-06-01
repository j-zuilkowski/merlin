import XCTest
@testable import Merlin

@MainActor
final class AgenticEngineTests: XCTestCase {

    func testSimpleTurn() async throws {
        let provider = MockProvider(chunks: [
            .init(delta: .init(content: "hello world"), finishReason: nil),
            .init(delta: .init(content: nil), finishReason: "stop"),
        ])
        let engine = makeEngine(provider: provider)
        var collected = ""
        for await event in engine.send(userMessage: "hi") {
            if case .text(let t) = event { collected += t }
        }
        XCTAssertEqual(collected, "hello world")
    }

    func testToolCallLoop() async throws {
        let provider = MockProvider(responses: [
            MockLLMResponse.toolCall(id: "tc1", name: "echo_tool", args: #"{"value":"ping"}"#),
            MockLLMResponse.text("pong received"),
        ])
        let engine = makeEngine(provider: provider)
        engine.registerTool("echo_tool") { args in
            let data = args.data(using: .utf8)!
            let json = try JSONSerialization.jsonObject(with: data) as! [String: String]
            return json["value"] ?? ""
        }

        var finalText = ""
        for await event in engine.send(userMessage: "call echo") {
            if case .text(let t) = event { finalText += t }
        }
        XCTAssertTrue(finalText.contains("pong received"))
    }

    func testTextEncodedFunctionToolCallExecutes() async throws {
        let provider = MockProvider(responses: [
            MockLLMResponse.text("""
            I'll read the file now.
            <function=echo_tool>
            <parameter=value>
            ping
            </parameter>
            </function>
            </tool_call>
            """),
            MockLLMResponse.text("pong received"),
        ])
        let engine = makeEngine(provider: provider)
        engine.registerTool("echo_tool") { args in
            let data = args.data(using: .utf8)!
            let json = try JSONSerialization.jsonObject(with: data) as! [String: String]
            return json["value"] ?? ""
        }

        var toolStarted = false
        var finalText = ""
        for await event in engine.send(userMessage: "call echo") {
            switch event {
            case .toolCallStarted(let call):
                toolStarted = call.function.name == "echo_tool"
            case .text(let text):
                finalText += text
            default:
                break
            }
        }

        XCTAssertTrue(toolStarted)
        XCTAssertTrue(finalText.contains("pong received"))
    }

    func testTextEncodedFunctionToolCallIgnoresUnofferedTools() async throws {
        let provider = MockProvider(response: """
        <function=unknown_tool>
        <parameter=value>ping</parameter>
        </function>
        """)
        let engine = makeEngine(provider: provider)

        var sawTool = false
        for await event in engine.send(userMessage: "call unknown") {
            if case .toolCallStarted = event {
                sawTool = true
            }
        }

        XCTAssertFalse(sawTool)
    }

    func testElectronicsWorkflowToolCallIsExclusiveWithinTurn() {
        let engine = makeEngine()
        engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        let selected = engine.authoritativeToolCallNamesForTesting([
            "tool_discover",
            ElectronicsWorkflowRoute.requirementsToPCB.rawValue,
            "read_file",
            "kicad_run_spice",
        ])

        XCTAssertEqual(selected, [ElectronicsWorkflowRoute.requirementsToPCB.rawValue])
    }

    func testActiveElectronicsWorkflowLockHardStopsUnapprovedToolCalls() async throws {
        let provider = MockProvider(responses: [
            .toolCall(id: "drift", name: "app_focus", args: #"{"bundle_id":"com.apple.finder"}"#),
            .text("should not continue"),
        ])
        let engine = makeEngine(provider: provider)
        engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        engine.permissionMode = .autoAccept
        engine.toolRouter.registerWorkspaceCapabilityTools(ElectronicsRuntimePlugin().metadata.capabilities)

        var cleanStopSummary = ""
        var rejection = ""
        var finalText = ""
        for await event in engine.send(userMessage: "Run the AmpDemo electronics workflow") {
            switch event {
            case .cleanStop(let reason, let summary):
                cleanStopSummary = "\(reason): \(summary)"
            case .toolCallResult(let result) where result.isError:
                rejection = result.content
            case .text(let text):
                finalText += text
            default:
                break
            }
        }

        XCTAssertEqual(provider.callCount, 1)
        XCTAssertTrue(cleanStopSummary.contains("electronics workflow drift"), cleanStopSummary)
        XCTAssertTrue(rejection.contains("not approved while the electronics workflow lock is active"), rejection)
        XCTAssertFalse(finalText.contains("should not continue"))
    }

    func testActiveElectronicsWorkflowLockRejectsXcodeOpenFile() async throws {
        let provider = MockProvider(responses: [
            .toolCall(
                id: "drift",
                name: "xcode_open_file",
                args: #"{"path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo/kicad/AmpDemo.kicad_pro","line":1}"#
            ),
            .text("should not continue"),
        ])
        let engine = makeEngine(provider: provider)
        engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        engine.permissionMode = .autoAccept
        engine.toolRouter.registerWorkspaceCapabilityTools(ElectronicsRuntimePlugin().metadata.capabilities)

        var cleanStopSummary = ""
        var rejection = ""
        var finalText = ""
        for await event in engine.send(userMessage: "Read the spec, then invoke the first KiCad electronics tool") {
            switch event {
            case .cleanStop(let reason, let summary):
                cleanStopSummary = "\(reason): \(summary)"
            case .toolCallResult(let result) where result.isError:
                rejection = result.content
            case .text(let text):
                finalText += text
            default:
                break
            }
        }

        XCTAssertEqual(provider.callCount, 1)
        XCTAssertTrue(cleanStopSummary.contains("electronics workflow drift"), cleanStopSummary)
        XCTAssertTrue(rejection.contains("xcode_open_file"), rejection)
        XCTAssertTrue(rejection.contains("not approved while the electronics workflow lock is active"), rejection)
        XCTAssertFalse(finalText.contains("should not continue"))
    }

    func testActiveElectronicsWorkflowLockRejectsXcodeToolWithoutRuntimeTools() async throws {
        let provider = MockProvider(responses: [
            .toolCall(
                id: "drift",
                name: "xcode_spm_list",
                args: #"{"path":"/Users/jonzuilkowski/Documents/localProject/AmpDemo"}"#
            ),
            .text("should not continue"),
        ])
        let engine = makeEngine(provider: provider)
        engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        engine.permissionMode = .autoAccept

        var cleanStopSummary = ""
        var rejection = ""
        var finalText = ""
        for await event in engine.send(userMessage: "Read the spec, then invoke the first KiCad electronics tool") {
            switch event {
            case .cleanStop(let reason, let summary):
                cleanStopSummary = "\(reason): \(summary)"
            case .toolCallResult(let result) where result.isError:
                rejection = result.content
            case .text(let text):
                finalText += text
            default:
                break
            }
        }

        XCTAssertEqual(provider.callCount, 1)
        XCTAssertTrue(cleanStopSummary.contains("electronics workflow drift"), cleanStopSummary)
        XCTAssertTrue(rejection.contains("xcode_spm_list"), rejection)
        XCTAssertTrue(rejection.contains("not approved while the electronics workflow lock is active"), rejection)
        XCTAssertFalse(finalText.contains("should not continue"))
    }

    func testActiveElectronicsReadOnlyNarrativeCannotSatisfyRequestedToolBoundary() async throws {
        ToolRegistry.shared.registerBuiltins()
        let provider = MockProvider(responses: [
            .toolCall(
                id: "read",
                name: "read_file",
                args: #"{"path":"/tmp/AmpDemo/spec.md"}"#
            ),
            .text("""
            I read the spec. The first actual electronics tool invocation would occur later after GUI setup.
            Blocker: I cannot invoke electronics tools yet because the workflow requires GUI automation setup.
            """),
            .toolCall(
                id: "intent",
                name: "kicad_build_intent_model",
                args: #"{"input_artifact_path":"/tmp/AmpDemo/spec.md","board_profile_id":"amp_low_voltage_audio"}"#
            ),
            .text("should not continue"),
        ])
        let engine = makeEngine(provider: provider)
        engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        engine.permissionMode = .autoAccept
        engine.toolRouter.registerWorkspaceCapabilityTools(ElectronicsRuntimePlugin().metadata.capabilities)
        engine.registerTool("read_file") { _ in "AmpDemo 25W Class-A amplifier requirements" }
        engine.registerTool("kicad_build_intent_model") { _ in
            #"{"status":"draft","artifacts":[{"kind":"design_intent","path":"/tmp/AmpDemo/.merlin/electronics-artifacts/design_intent.json"}]}"#
        }

        var toolNames: [String] = []
        var notes: [String] = []
        var finalText = ""
        for await event in engine.send(
            userMessage: "Using the electronics domain, read /tmp/AmpDemo/spec.md, then stop after the first real electronics plugin/KiCad tool invocation is attempted or completed."
        ) {
            switch event {
            case .toolCallStarted(let call):
                toolNames.append(call.function.name)
            case .systemNote(let note):
                notes.append(note)
            case .text(let text):
                finalText += text
            default:
                break
            }
        }

        XCTAssertEqual(toolNames, ["read_file", "kicad_build_intent_model"])
        XCTAssertTrue(
            notes.contains { $0.contains("read-only/prose response cannot satisfy requested electronics tool boundary") },
            notes.joined(separator: "\n")
        )
        XCTAssertTrue(
            notes.contains { $0.contains("requested stop boundary satisfied") },
            notes.joined(separator: "\n")
        )
        XCTAssertFalse(finalText.contains("should not continue"))
    }

    func testDesignProducingElectronicsBoundaryIgnoresKiCadHealthCheck() {
        let engine = makeEngine()
        let task = "Using the electronics domain, read /tmp/AmpDemo/spec.md, then stop after the first design-producing electronics/KiCad tool invocation is attempted or completed."

        XCTAssertFalse(engine.requestedStopBoundaryMatchesForTesting(
            task: task,
            toolName: "kicad_check_version"
        ))
        XCTAssertTrue(engine.requestedStopBoundaryMatchesForTesting(
            task: task,
            toolName: "kicad_build_intent_model"
        ))
        XCTAssertTrue(engine.requestedStopBoundaryMatchesForTesting(
            task: task,
            toolName: "kicad_generate_circuit_ir"
        ))
    }

    func testCompletedElectronicsWorkflowResultStopsWithoutNarrativeContinuation() async throws {
        let originalCriticEnabled = AppSettings.shared.criticEnabled
        AppSettings.shared.criticEnabled = false
        defer { AppSettings.shared.criticEnabled = originalCriticEnabled }

        let provider = MockProvider(responses: [
            .toolCall(
                id: "workflow",
                name: ElectronicsWorkflowRoute.requirementsToPCB.rawValue,
                args: #"{"requirements":"25W Class A guitar amplifier"}"#
            ),
            .text("should not summarize after terminal workflow result"),
        ])
        let engine = makeEngine(provider: provider)
        engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        engine.permissionMode = .autoAccept
        engine.toolRouter.registerWorkspaceCapabilityTools(ElectronicsRuntimePlugin().metadata.capabilities)
        engine.registerTool(ElectronicsWorkflowRoute.requirementsToPCB.rawValue) { _ in
            """
            {"jobId":"ampdemo","status":"COMPLETE","artifacts":[{"kind":"kicad_schematic","path":"/tmp/amp.kicad_sch"},{"kind":"spice_measurements","path":"/tmp/amp-spice.log"},{"kind":"fabrication_package","path":"/tmp/fab.zip"},{"kind":"bom","path":"/tmp/bom.csv"}],"gates":[{"gate":"erc","status":"PASS","details":"pass"},{"gate":"simulation","status":"PASS","details":"pass"},{"gate":"fabrication","status":"PASS","details":"pass"}],"approvals":[],"blockedReasons":[]}
            """
        }

        var terminalNote = ""
        var finalText = ""
        for await event in engine.send(userMessage: "Run the AmpDemo electronics workflow") {
            switch event {
            case .systemNote(let note) where note.contains("electronics workflow complete"):
                terminalNote = note
            case .text(let text):
                finalText += text
            default:
                break
            }
        }

        XCTAssertEqual(provider.callCount, 1)
        XCTAssertTrue(terminalNote.contains("verified workflow result"), terminalNote)
        XCTAssertFalse(finalText.contains("should not summarize"))
    }

    func testBlockedElectronicsWorkflowResultStopsWithoutReadOnlyContinuation() async throws {
        struct BlockedToolError: Error {}

        let provider = MockProvider(responses: [
            .toolCall(
                id: "workflow",
                name: ElectronicsWorkflowRoute.requirementsToPCB.rawValue,
                args: #"{"requirements":"25W Class A guitar amplifier"}"#
            ),
            .toolCall(
                id: "read-after-block",
                name: "read_file",
                args: #"{"path":"/tmp/AmpDemo/spec.md"}"#
            ),
            .text("should not continue after blocked workflow"),
        ])
        let engine = makeEngine(provider: provider)
        engine.activeDomainIDs = [SoftwareDomain.defaultID, ElectronicsDomain.defaultID]
        engine.permissionMode = .autoAccept
        engine.registerTool(ElectronicsWorkflowRoute.requirementsToPCB.rawValue) { _ in
            throw BlockedToolError()
        }
        engine.registerTool("read_file") { _ in "spec contents" }

        var cleanStopSummary = ""
        var toolNames: [String] = []
        var finalText = ""
        for await event in engine.send(userMessage: "Run the AmpDemo electronics workflow") {
            switch event {
            case .toolCallStarted(let call):
                toolNames.append(call.function.name)
            case .cleanStop(let reason, let summary):
                cleanStopSummary = "\(reason): \(summary)"
            case .text(let text):
                finalText += text
            default:
                break
            }
        }

        XCTAssertEqual(provider.callCount, 1)
        XCTAssertEqual(toolNames, [ElectronicsWorkflowRoute.requirementsToPCB.rawValue])
        XCTAssertTrue(cleanStopSummary.contains("electronics workflow blocked"), cleanStopSummary)
        XCTAssertTrue(cleanStopSummary.contains(ElectronicsWorkflowRoute.requirementsToPCB.rawValue), cleanStopSummary)
        XCTAssertFalse(finalText.contains("should not continue"))
    }

    func testProviderSelectionFlash() async throws {
        let flash = MockProvider(chunks: [.init(delta: .init(content: "ok"), finishReason: "stop")])
        flash.id_ = "deepseek-v4-flash"
        let pro = MockProvider(chunks: [])
        pro.id_ = "deepseek-v4-pro"
        let engine = makeEngine(proProvider: pro, flashProvider: flash)
        for await _ in engine.send(userMessage: "read the file at /tmp/test.txt") {}
        XCTAssertTrue(flash.wasUsed)
        XCTAssertFalse(pro.wasUsed)
    }

    func testContextCompactionNoteAppears() async throws {
        let provider = MockProvider(responses: [
            MockLLMResponse.toolCall(id: "tc1", name: "inflate_tool", args: #"{"value":"go"}"#),
            MockLLMResponse.text("done"),
        ])
        let engine = makeEngine(provider: provider)
        engine.registerTool("inflate_tool") { _ in
            String(repeating: "z", count: 3_000_000)
        }

        for _ in 0..<97 {
            engine.contextManager.append(Message(
                role: .tool,
                content: .text(String(repeating: "y", count: 28_000)),
                toolCallId: "seed",
                timestamp: Date()
            ))
        }

        var events: [AgentEvent] = []
        for await e in engine.send(userMessage: "trigger compaction") {
            events.append(e)
        }
        XCTAssertTrue(events.contains {
            if case .systemNote(let note) = $0 { return note.contains("compacted") }
            return false
        })
    }
}
