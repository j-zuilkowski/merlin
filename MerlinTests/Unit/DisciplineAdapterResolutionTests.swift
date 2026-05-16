import XCTest
@testable import Merlin

/// Phase 290a — failing tests for real adapter selection.
///
/// `DisciplineEngine` is constructed with `ProjectAdapter.makeStub` and the loaded
/// `AdapterRegistry` is never read. These tests pin the new surface that makes the
/// engine use the project's real adapter from `.merlin/project.toml`.
final class DisciplineAdapterResolutionTests: XCTestCase {

    private func makeTmpProject() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dar-\(UUID())", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeEngine(projectRoot: URL) -> DisciplineEngine {
        DisciplineEngine(
            adapter: .makeStub(language: "swift"),
            phaseScanner: PhaseScanner(),
            manualCoverageScanner: ManualCoverageScanner(),
            docReferenceGraph: DocReferenceGraph(),
            whyCommentScanner: WhyCommentScanner(),
            proseReadabilityChecker: ProseReadabilityChecker(dryRun: true),
            storePath: projectRoot.appendingPathComponent(".merlin/pending.json").path
        )
    }

    func testSetAdapterUpdatesEngineAdapter() async {
        let engine = makeEngine(projectRoot: makeTmpProject())
        let real = ProjectAdapter.makeStub(language: "rust", buildCommand: "cargo build")
        await engine.setAdapter(real)
        let current = await engine.currentAdapter()
        XCTAssertEqual(current, real)
    }

    func testResolveReturnsStubWhenNoConfig() async {
        let project = makeTmpProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let adapter = await DisciplineEngine.resolveProjectAdapter(
            projectPath: project.path, registry: AdapterRegistry())
        XCTAssertEqual(adapter.language, "swift", "no .merlin/project.toml → stub fallback")
    }

    func testResolveLoadsConfiguredAdapter() async throws {
        let project = makeTmpProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let config = ProjectConfig(
            adapter: "rust-cargo", adapterVersion: "1.0",
            disciplineLayers: ["soft_prompt"], manualCoverageBaseline: 0, decayPerRelease: 10)
        try await ProjectConfigLoader().save(config, projectPath: project.path)

        let registry = AdapterRegistry()
        let rust = ProjectAdapter.makeStub(language: "rust", buildCommand: "cargo build")
        await registry.register(rust, for: "rust-cargo")

        let resolved = await DisciplineEngine.resolveProjectAdapter(
            projectPath: project.path, registry: registry)
        XCTAssertEqual(resolved, rust)
    }

    func testResolveFallsBackWhenAdapterKeyUnknown() async throws {
        let project = makeTmpProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let config = ProjectConfig(
            adapter: "nonexistent", adapterVersion: "1.0",
            disciplineLayers: [], manualCoverageBaseline: 0, decayPerRelease: 10)
        try await ProjectConfigLoader().save(config, projectPath: project.path)

        let resolved = await DisciplineEngine.resolveProjectAdapter(
            projectPath: project.path, registry: AdapterRegistry())
        XCTAssertEqual(resolved.language, "swift", "unknown adapter key → stub fallback")
    }
}
