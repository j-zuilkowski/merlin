import XCTest
@testable import Merlin

@MainActor
final class ElectronicsRoutingBackendTests: XCTestCase {
    func testMissingLocalFreeRoutingBlocksWithTypedReason() async throws {
        let backend = LocalFreeRoutingBackend(
            executableURL: URL(fileURLWithPath: "/missing/freerouting"),
            fileExists: { _ in false },
            runner: RecordingFreeRoutingRunner()
        )

        let health = await backend.health()

        XCTAssertEqual(health.status, .blockedTooling)
        XCTAssertEqual(health.blockedReason, .missingFreeRouting)
    }

    func testRoutePassUsesDSNSESAndPublishesProgressAndArtifacts() async throws {
        let runtime = try WorkspaceRuntime(
            rootURL: URL(fileURLWithPath: "/tmp/electronics-routing"),
            merlinHomeURL: FileManager.default.temporaryDirectory.appendingPathComponent("merlin-routing-\(UUID().uuidString)")
        )
        let runner = RecordingFreeRoutingRunner()
        let backend = LocalFreeRoutingBackend(
            executableURL: URL(fileURLWithPath: "/Applications/freerouting.app/Contents/MacOS/freerouting"),
            fileExists: { _ in true },
            runner: runner
        )

        let request = LocalFreeRoutingRequest(
            jobID: "job-1",
            boardURL: runtime.rootURL.appendingPathComponent("board.kicad_pcb"),
            dsnURL: runtime.rootURL.appendingPathComponent("board.dsn"),
            sesURL: runtime.rootURL.appendingPathComponent("board.ses"),
            logURL: runtime.rootURL.appendingPathComponent("route.log"),
            maxIterations: 3
        )

        let result = await backend.route(request, bus: runtime.bus, origin: origin(runtime))

        XCTAssertEqual(result.status, .complete)
        XCTAssertEqual(runner.invocations.count, 1)
        XCTAssertTrue(runner.invocations[0].arguments.contains(request.dsnURL.path))
        XCTAssertTrue(runner.invocations[0].arguments.contains(request.sesURL.path))
        XCTAssertTrue(result.artifacts.map(\.kind).contains(ElectronicsArtifactKind.routingInterchange.rawValue))
        XCTAssertTrue(result.artifacts.map(\.kind).contains(ElectronicsArtifactKind.routingResult.rawValue))

        let events = await runtime.bus.recentEvents(matching: WorkspaceMessageEventFilter(namespacePrefix: "plugin.electronics"))
        XCTAssertTrue(events.contains { $0.kind == .progress })
        XCTAssertTrue(events.contains { $0.kind == .artifactProduced })
    }

    func testHostedRoutingIsOptionalAndNotUsedByDefault() async throws {
        let backend = LocalFreeRoutingBackend(
            executableURL: URL(fileURLWithPath: "/Applications/freerouting.app/Contents/MacOS/freerouting"),
            fileExists: { _ in true },
            runner: RecordingFreeRoutingRunner()
        )

        XCTAssertEqual(backend.routingBackend, .localFreeRouting)
        XCTAssertEqual(ElectronicsCompletionContract.current.hostedRoutingPolicy, .optionalConfigured)
    }

    private func origin(_ runtime: WorkspaceRuntime) -> WorkspaceMessageOrigin {
        WorkspaceMessageOrigin.parentSession(
            workspaceID: runtime.workspaceID,
            sessionID: nil,
            activeDomainIDs: [ElectronicsDomain.defaultID],
            permissionScope: .externalSideEffect
        )
    }
}

private final class RecordingFreeRoutingRunner: FreeRoutingProcessRunning, @unchecked Sendable {
    struct Invocation {
        var executableURL: URL
        var arguments: [String]
    }

    var invocations: [Invocation] = []

    func run(executableURL: URL, arguments: [String], timeoutSeconds: Int) async -> FreeRoutingProcessResult {
        invocations.append(Invocation(executableURL: executableURL, arguments: arguments))
        return FreeRoutingProcessResult(exitCode: 0, stdout: "100% routed", stderr: "")
    }
}
