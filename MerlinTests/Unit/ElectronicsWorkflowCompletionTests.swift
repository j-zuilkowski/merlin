import XCTest
@testable import Merlin

@MainActor
final class ElectronicsWorkflowCompletionTests: XCTestCase {
    func testCompleteEvidenceProducesFinalReportForBothWorkflows() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)

        let payload = try workflowPayload(jobID: "job-complete", highStakes: false)
        for capability in ["workflow.schematic_to_pcb", "workflow.requirements_to_pcb"] {
            let response = await sendElectronics(runtime, capability: capability, payload: payload)
            XCTAssertEqual(response.status, WorkspaceMessageResponseStatus.ok, capability)
            let report = try XCTUnwrap(response.payload?.decodeJSON(ElectronicsFinalReport.self))
            XCTAssertEqual(report.status, .complete)
            XCTAssertFalse(report.artifacts.isEmpty)
        }
    }

    func testIncompleteEvidenceBlocksWorkflow() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let payload = #"{"job_id":"incomplete","evidence":{"artifacts":[],"gates":{},"approvals":[],"high_stakes":false}}"#

        let response = await sendElectronics(runtime, capability: "workflow.schematic_to_pcb", payload: payload)
        XCTAssertEqual(response.status, WorkspaceMessageResponseStatus.blocked)
        XCTAssertEqual(response.diagnostics.first?.code, ElectronicsBlockedReason.missingArtifact.rawValue)
    }

    func testRequirementsWorkflowBlocksPromptOnlyCompletionInsteadOfSynthesizingArtifacts() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let output = temporaryDirectory("requirements-to-pcb")
        let ngspice = try writeFakeNgspice()
        let payload = #"{"job_id":"s6","requirements":"555 astable LED blinker","output_directory":"\#(output.path)","high_stakes":false,"ngspice_path":"\#(ngspice.path)"}"#

        let response = await sendElectronics(runtime, capability: "workflow.requirements_to_pcb", payload: payload)
        XCTAssertEqual(response.status, WorkspaceMessageResponseStatus.blocked)
        XCTAssertEqual(response.diagnostics.first?.code, ElectronicsBlockedReason.missingArtifact.rawValue)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("merlin-board.kicad_pro").path))
    }

    func testAmpDemoRequirementsWorkflowRunsKiCadSpiceAndWritesEvidence() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let output = temporaryDirectory("ampdemo-requirements-to-pcb")
        let kicadCLI = try writeFakeKiCadCLI()
        let ngspice = try writeFakeNgspice()
        let payload = """
        {
          "job_id": "ampdemo-test",
          "requirements": "Design a 25 watt pure Class A solid-state guitar amplifier for guitar with transformer-isolated North American mains.",
          "output_directory": "\(output.path)",
          "kicad_cli_path": "\(kicadCLI.path)",
          "ngspice_path": "\(ngspice.path)",
          "high_stakes": false
        }
        """

        let response = await sendElectronics(runtime, capability: "workflow.requirements_to_pcb", payload: payload)

        XCTAssertEqual(response.status, .ok)
        let report = try XCTUnwrap(response.payload?.decodeJSON(ElectronicsFinalReport.self))
        XCTAssertEqual(report.status, .complete)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("kicad/AmpDemo.kicad_pro").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("kicad/AmpDemo.kicad_sch").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("kicad/AmpDemo.kicad_pcb").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("gerbers/AmpDemo-job.gbrjob").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("drill/AmpDemo.drl").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("simulation/ngspice-output.log").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("bom/ampdemo-bom.csv").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("reports/final-demo-report.md").path))
        let schematic = try String(contentsOf: output.appendingPathComponent("kicad/AmpDemo.kicad_sch"), encoding: .utf8)
        let board = try String(contentsOf: output.appendingPathComponent("kicad/AmpDemo.kicad_pcb"), encoding: .utf8)
        XCTAssertGreaterThanOrEqual(schematic.components(separatedBy: "(text").count - 1, 16)
        XCTAssertTrue(schematic.contains("QOUT1"))
        XCTAssertTrue(schematic.contains("3-band tone stack"))
        XCTAssertTrue(schematic.contains("sweepable boost/cut"))
        XCTAssertGreaterThanOrEqual(board.components(separatedBy: "(footprint").count - 1, 8)
        XCTAssertGreaterThanOrEqual(board.components(separatedBy: "(pad").count - 1, 16)
        XCTAssertGreaterThanOrEqual(board.components(separatedBy: "(segment").count - 1, 8)
        XCTAssertTrue(board.contains("JSEC"))
        XCTAssertTrue(board.contains("QOUT1"))
        let bom = try String(contentsOf: output.appendingPathComponent("bom/ampdemo-bom.csv"), encoding: .utf8)
        XCTAssertTrue(bom.contains("Digi-Key"))
        XCTAssertTrue(bom.contains("Mouser"))

        let store = ElectronicsJobStore()
        await store.loadRecent(from: runtime.bus)
        let job = try XCTUnwrap(store.jobs.first { $0.id == "ampdemo-test" })
        XCTAssertEqual(job.status, .complete)
        XCTAssertFalse(job.progress.isEmpty)
        let completedProgressMessages = job.progress.map(\.message)
        XCTAssertTrue(completedProgressMessages.contains("KiCad ERC passed"))
        XCTAssertTrue(completedProgressMessages.contains("KiCad DRC passed"))
        XCTAssertTrue(completedProgressMessages.contains("Gerbers exported"))
        XCTAssertTrue(completedProgressMessages.contains("Drill files exported"))
        XCTAssertTrue(completedProgressMessages.contains("ngspice simulation passed"))
        XCTAssertFalse(completedProgressMessages.contains { message in
            message.hasPrefix("Running ") || message.hasPrefix("Exporting ") || message.hasPrefix("Packaging ")
        })
        XCTAssertFalse(job.artifacts.isEmpty)
        XCTAssertEqual(job.reports.first?.status, .complete)
    }

    func testRunSpiceRejectsSummaryLogsBeforeInvokingNgspice() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let output = temporaryDirectory("spice-invalid-input")
        let project = output.appendingPathComponent("project.kicad_pro")
        let summary = output.appendingPathComponent("spice.log")
        try "{}".write(to: project, atomically: true, encoding: .utf8)
        try "555 astable transient simulation\noscillation=pass\n".write(to: summary, atomically: true, encoding: .utf8)

        let response = await sendElectronics(
            runtime,
            capability: "kicad_run_spice",
            payload: #"{"project_path":"\#(project.path)","scenario_path":"\#(summary.path)"}"#
        )

        XCTAssertEqual(response.status, .blocked)
        XCTAssertEqual(response.diagnostics.first?.code, ElectronicsBlockedReason.invalidInputQuality.rawValue)
    }

    func testRequirementsWorkflowDoesNotCreateKiCadProjectForPromptOnlyRequest() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let output = temporaryDirectory("requirements-to-pcb-erc")
        let project = output.appendingPathComponent("merlin-board.kicad_pro").path
        let ngspice = try writeFakeNgspice()
        let payload = #"{"job_id":"s6-erc","requirements":"555 astable LED blinker","output_directory":"\#(output.path)","high_stakes":false,"ngspice_path":"\#(ngspice.path)"}"#

        let workflow = await sendElectronics(runtime, capability: "workflow.requirements_to_pcb", payload: payload)
        XCTAssertEqual(workflow.status, WorkspaceMessageResponseStatus.blocked)
        XCTAssertFalse(FileManager.default.fileExists(atPath: project))
    }

    func testWorkflowBlocksMismatched555ArtifactsForAmplifierRequest() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let evidence = try fake555Evidence()
        let request = ElectronicsWorkflowRequest(jobID: "amp-mismatch", evidence: evidence)
        var object = try JSONSerialization.jsonObject(with: WorkspaceJSON.encoder.encode(request)) as? [String: Any] ?? [:]
        object["requirements"] = "Design a 25 watt class-A guitar amplifier with a 3-band tone stack."
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let payload = String(data: data, encoding: .utf8) ?? "{}"

        let response = await sendElectronics(runtime, capability: "workflow.requirements_to_pcb", payload: payload)
        XCTAssertEqual(response.status, WorkspaceMessageResponseStatus.blocked)
        XCTAssertTrue(response.diagnostics.contains { $0.message.contains("555/LED blinker") })
        let report = try XCTUnwrap(response.payload?.decodeJSON(ElectronicsFinalReport.self))
        XCTAssertEqual(report.status, .blocked)
        XCTAssertEqual(report.gates.first { $0.gate == .parity }?.status, .fail)
    }

    func testHighStakesWorkflowBlocksWithoutSignoff() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)
        let payload = try workflowPayload(jobID: "job-high", highStakes: true, approvals: [])

        let response = await sendElectronics(runtime, capability: "workflow.requirements_to_pcb", payload: payload)
        XCTAssertEqual(response.status, WorkspaceMessageResponseStatus.blocked)
        XCTAssertTrue(response.diagnostics.contains { $0.code == ElectronicsBlockedReason.failedGate.rawValue })
    }

    func testOrderSubmissionRequiresExplicitApproval() async throws {
        let runtime = try testRuntime()
        try await ElectronicsRuntimePlugin().register(into: runtime)

        let response = await sendElectronics(runtime, capability: "kicad_submit_vendor_order", payload: #"{"job_id":"order-1"}"#, scope: .userApprovedIrreversible)
        XCTAssertEqual(response.status, WorkspaceMessageResponseStatus.blocked)
        XCTAssertEqual(response.diagnostics.first?.code, "APPROVAL_REQUIRED")
    }

    private func writeFakeNgspice() throws -> URL {
        let directory = temporaryDirectory("fake-ngspice")
        let executable = directory.appendingPathComponent("ngspice")
        let script = """
        #!/bin/sh
        output=""
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "-o" ]; then
            shift
            output="$1"
          fi
          shift
        done
        if [ -z "$output" ]; then
          exit 2
        fi
        mkdir -p "$(dirname "$output")"
        printf 'frequency = 1.40\\n' > "$output"
        exit 0
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return executable
    }

    private func writeFakeKiCadCLI() throws -> URL {
        let directory = temporaryDirectory("fake-kicad")
        let executable = directory.appendingPathComponent("kicad-cli")
        let script = """
        #!/bin/sh
        original="$*"
        case "$*" in
          *"--version"*) echo "KiCad Version: 10.0.0"; exit 0 ;;
        esac
        output=""
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "--output" ]; then
            shift
            output="$1"
          fi
          shift
        done
        case "$original" in
          *"export gerbers"*)
            mkdir -p "$output"
            printf 'gerber job\\n' > "$output/AmpDemo-job.gbrjob"
            exit 0
            ;;
          *"export drill"*)
            mkdir -p "$output"
            printf 'drill\\n' > "$output/AmpDemo.drl"
            exit 0
            ;;
        esac
        if [ -n "$output" ]; then
          mkdir -p "$(dirname "$output")"
          printf '{"status":"pass"}\\n' > "$output"
        fi
        exit 0
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return executable
    }

    private func fake555Evidence() throws -> ElectronicsCompletionEvidence {
        let directory = temporaryDirectory("fake-555-evidence")
        let files: [(ElectronicsArtifactKind, String, String)] = [
            (.kicadProject, "merlin-board.kicad_pro", #"{"meta":{"version":1}}"#),
            (.schematic, "merlin-board.kicad_sch", "555 astable LED blinker using NE555\n"),
            (.board, "merlin-board.kicad_pcb", "(kicad_pcb (version 20250114))\n"),
            (.routingInterchange, "merlin-board.dsn", "dsn\n"),
            (.routingResult, "merlin-board.ses", "ses\n"),
            (.bom, "bom.csv", "RefDes,Value,MPN,DigiKey,Mouser,Quantity\nU1,NE555,NE555P,296-NE555P-ND,595-NE555P,1\n"),
            (.pickAndPlace, "centroid.csv", "Designator,Mid X,Mid Y,Layer,Rotation\nU1,1,1,F.Cu,0\n"),
            (.spiceMeasurements, "spice-run.log", "555 astable transient frequency = 1.4\n"),
            (.verificationReport, "verification.json", #"{"status":"COMPLETE"}"#),
            (.approvalRecord, "approvals.json", #"{"approved":true}"#),
        ]
        var artifacts: [ElectronicsCompletionArtifact] = []
        for (kind, name, body) in files {
            let url = directory.appendingPathComponent(name)
            try body.write(to: url, atomically: true, encoding: .utf8)
            artifacts.append(ElectronicsCompletionArtifact(kind: kind, path: url.path))
        }
        let fabURL = directory.appendingPathComponent("fab.zip")
        try Data([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00]).write(to: fabURL)
        artifacts.append(ElectronicsCompletionArtifact(kind: .fabricationPackage, path: fabURL.path))

        return ElectronicsCompletionEvidence(
            artifacts: artifacts,
            gates: ElectronicsGateResult.allPassingRequired,
            approvals: [],
            highStakes: false
        )
    }
}
