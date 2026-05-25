# Phase 242a — ProjectConfig Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 241b complete: AdapterRegistry, ProjectAdapter, WHYTriggerSpec, ManualCoveragePattern,
TOMLAdapterParser, and seed adapters live.

Introduces the per-project configuration file (`.merlin/project.toml`) and its loader.
Every discipline component reads from `ProjectConfig` rather than hard-coded paths.

New surface introduced in phase 242b:
  - `ProjectConfig: Sendable, Codable` in `Merlin/Discipline/ProjectConfig.swift`:
    `adapter: String`, `adapterVersion: String`, `disciplineLayers: [String]`,
    `manualCoverageBaseline: Int`, `decayPerRelease: Int`.
  - `ProjectConfigLoader` in `Merlin/Discipline/ProjectConfigLoader.swift`:
    `func load(projectPath: String) async throws -> ProjectConfig`
    `func save(_ config: ProjectConfig, projectPath: String) async throws`
    `func exists(projectPath: String) -> Bool`
  - `ProjectConfigLoader.defaultConfig(adapter: String) -> ProjectConfig` — baseline 0,
    decayPerRelease 10, layers `["soft_prompt", "pre_commit"]`.

TDD coverage:
  File 1 — `MerlinTests/Unit/ProjectConfigTests.swift`: `ProjectConfig` Codable round-trip;
    `defaultConfig` produces correct field values; optional fields default correctly when absent
    from TOML.
  File 2 — `MerlinTests/Unit/ProjectConfigLoaderTests.swift`: `load` reads a TOML file and
    returns a matching `ProjectConfig`; `save` writes TOML that `load` can re-read; `exists`
    returns false when `.merlin/project.toml` is absent, true when present.

---

## Write to

- `MerlinTests/Unit/ProjectConfigTests.swift`
- `MerlinTests/Unit/ProjectConfigLoaderTests.swift`

### MerlinTests/Unit/ProjectConfigTests.swift

```swift
import XCTest
@testable import Merlin

final class ProjectConfigTests: XCTestCase {

    // MARK: - Codable round-trip

    func testCodableRoundTrip() throws {
        let config = ProjectConfig(
            adapter: "swift-xcode",
            adapterVersion: "1.0",
            disciplineLayers: ["soft_prompt", "pre_commit"],
            manualCoverageBaseline: 42,
            decayPerRelease: 10
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ProjectConfig.self, from: data)
        XCTAssertEqual(decoded.adapter, "swift-xcode")
        XCTAssertEqual(decoded.adapterVersion, "1.0")
        XCTAssertEqual(decoded.disciplineLayers, ["soft_prompt", "pre_commit"])
        XCTAssertEqual(decoded.manualCoverageBaseline, 42)
        XCTAssertEqual(decoded.decayPerRelease, 10)
    }

    // MARK: - defaultConfig

    func testDefaultConfig() {
        let config = ProjectConfigLoader.defaultConfig(adapter: "rust-cargo")
        XCTAssertEqual(config.adapter, "rust-cargo")
        XCTAssertEqual(config.manualCoverageBaseline, 0)
        XCTAssertEqual(config.decayPerRelease, 10)
        XCTAssertTrue(config.disciplineLayers.contains("soft_prompt"))
        XCTAssertTrue(config.disciplineLayers.contains("pre_commit"))
    }
}
```

### MerlinTests/Unit/ProjectConfigLoaderTests.swift

```swift
import XCTest
@testable import Merlin

final class ProjectConfigLoaderTests: XCTestCase {

    private func makeTmpProject() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - exists

    func testExistsReturnsFalseWhenAbsent() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        let loader = ProjectConfigLoader()
        XCTAssertFalse(loader.exists(projectPath: proj.path))
    }

    func testExistsReturnsTrueWhenPresent() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        let dotMerlin = proj.appendingPathComponent(".merlin")
        try FileManager.default.createDirectory(at: dotMerlin, withIntermediateDirectories: true)
        let toml = "adapter = \"swift-xcode\"\nadapter_version = \"1.0\"\n"
        try toml.write(to: dotMerlin.appendingPathComponent("project.toml"),
                       atomically: true, encoding: .utf8)
        let loader = ProjectConfigLoader()
        XCTAssertTrue(loader.exists(projectPath: proj.path))
    }

    // MARK: - load

    func testLoadParsesFields() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        let dotMerlin = proj.appendingPathComponent(".merlin")
        try FileManager.default.createDirectory(at: dotMerlin, withIntermediateDirectories: true)
        let toml = """
        adapter = "swift-xcode"
        adapter_version = "1.0"
        discipline_layers = ["soft_prompt", "pre_commit"]
        manual_coverage_baseline = 314
        decay_per_release = 10
        """
        try toml.write(to: dotMerlin.appendingPathComponent("project.toml"),
                       atomically: true, encoding: .utf8)
        let loader = ProjectConfigLoader()
        let config = try await loader.load(projectPath: proj.path)
        XCTAssertEqual(config.adapter, "swift-xcode")
        XCTAssertEqual(config.manualCoverageBaseline, 314)
        XCTAssertEqual(config.decayPerRelease, 10)
    }

    func testLoadThrowsWhenMissing() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        let loader = ProjectConfigLoader()
        do {
            _ = try await loader.load(projectPath: proj.path)
            XCTFail("Expected error when project.toml absent")
        } catch {
            // Any error is acceptable
        }
    }

    // MARK: - save + load round-trip

    func testSaveLoadRoundTrip() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        let config = ProjectConfig(
            adapter: "rust-cargo",
            adapterVersion: "1.0",
            disciplineLayers: ["soft_prompt"],
            manualCoverageBaseline: 7,
            decayPerRelease: 5
        )
        let loader = ProjectConfigLoader()
        try await loader.save(config, projectPath: proj.path)
        let loaded = try await loader.load(projectPath: proj.path)
        XCTAssertEqual(loaded.adapter, "rust-cargo")
        XCTAssertEqual(loaded.manualCoverageBaseline, 7)
        XCTAssertEqual(loaded.decayPerRelease, 5)
    }
}
```

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** with errors naming `ProjectConfig`, `ProjectConfigLoader`,
and `ProjectConfigLoader.defaultConfig`.

## Commit

```bash
git add tasks/task-242a-project-config-tests.md \
    MerlinTests/Unit/ProjectConfigTests.swift \
    MerlinTests/Unit/ProjectConfigLoaderTests.swift
git commit -m "Phase 242a — ProjectConfigTests (failing)"
```
