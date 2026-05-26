import XCTest
@testable import Merlin

@MainActor
final class WorkspaceRuntimeTests: XCTestCase {
    func testWorkspaceIDPersistsForCanonicalPath() throws {
        let home = temporaryDirectory()
        let project = home.appendingPathComponent("Project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

        let first = try WorkspaceRuntime(rootURL: project, merlinHomeURL: home.appendingPathComponent(".merlin"))
        let second = try WorkspaceRuntime(rootURL: project, merlinHomeURL: home.appendingPathComponent(".merlin"))

        XCTAssertEqual(first.workspaceID, second.workspaceID)
        XCTAssertFalse(first.workspaceID.isEmpty)
    }

    func testDifferentWorkspacePathsReceiveDifferentIDs() throws {
        let home = temporaryDirectory()
        let firstProject = home.appendingPathComponent("A")
        let secondProject = home.appendingPathComponent("B")
        try FileManager.default.createDirectory(at: firstProject, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondProject, withIntermediateDirectories: true)

        let first = try WorkspaceRuntime(rootURL: firstProject, merlinHomeURL: home.appendingPathComponent(".merlin"))
        let second = try WorkspaceRuntime(rootURL: secondProject, merlinHomeURL: home.appendingPathComponent(".merlin"))

        XCTAssertNotEqual(first.workspaceID, second.workspaceID)
    }

    func testWorkspaceStateAndSettingsPaths() throws {
        let home = temporaryDirectory()
        let project = home.appendingPathComponent("Project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

        let runtime = try WorkspaceRuntime(rootURL: project, merlinHomeURL: home.appendingPathComponent(".merlin"))

        XCTAssertEqual(
            runtime.stateRootURL.path,
            home.appendingPathComponent(".merlin/workspaces/\(runtime.workspaceID)").path
        )
        XCTAssertEqual(
            runtime.settingsURL(namespace: "plugin.electronics").path,
            runtime.stateRootURL.appendingPathComponent("settings/plugin.electronics.toml").path
        )
    }

    func testEventCapacityDefaultsAndClamps() throws {
        let home = temporaryDirectory()
        let project = home.appendingPathComponent("Project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

        let runtime = try WorkspaceRuntime(rootURL: project, merlinHomeURL: home.appendingPathComponent(".merlin"))
        XCTAssertEqual(runtime.eventCapacity, 1_000)
        XCTAssertEqual(WorkspaceRuntime.clampedEventCapacity(1), 100)
        XCTAssertEqual(WorkspaceRuntime.clampedEventCapacity(12_000), 10_000)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("merlin-runtime-tests-\(UUID().uuidString)", isDirectory: true)
    }
}
