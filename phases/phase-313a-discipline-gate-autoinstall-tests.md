# Phase 313a — Discipline Gate Auto-Install Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin.
Phase 312 complete: the Liveness Discipline batch (307–312) is committed.

Today the discipline pre-commit gate only activates when a user opens the app's Settings
and flips the discipline-hooks toggle (`SettingsWindowView.swift` `setDisciplineHooks`).
That is opt-in and easy to never enable — a prevention gate you can forget to turn on is
not a gate. This phase makes activation **automatic at app launch**: when a project that
has opted into the `pre_commit` discipline layer (its `.merlin/project.toml` lists
`pre_commit` in `discipline_layers`) is opened, the discipline binary and git hooks
install themselves.

The Settings toggle stays as a manual install/uninstall override — it is NOT removed.

New surface introduced in phase 313b:
  - `enum DisciplineGateInstaller` (in `Merlin/Discipline/`) with:
    - `static func wantsPreCommitGate(projectPath:) async -> Bool` — true when the
      project's `.merlin/project.toml` opts into the `pre_commit` layer.
    - `static func installIfConfigured(projectPath:) async -> Bool` — installs the
      binary + git hooks when `wantsPreCommitGate` is true; idempotent.
  - `AppState.init` calls `installIfConfigured` for the opened project.

TDD coverage:
  `MerlinTests/Unit/DisciplineGateInstallerTests.swift` — `wantsPreCommitGate` is the
  decision seam; it is pure (reads `.merlin/project.toml` only) and has no side effects,
  so it is the unit-tested surface. The install side effects and the `AppState` wiring
  are verified at runtime in 313b.

---

## Write to: MerlinTests/Unit/DisciplineGateInstallerTests.swift

```swift
import XCTest
@testable import Merlin

/// Phase 313a — failing tests for DisciplineGateInstaller.
final class DisciplineGateInstallerTests: XCTestCase {

    /// Builds a temp project; writes `.merlin/project.toml` only when `toml` is non-nil.
    private func makeProject(toml: String?) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gateinstall-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let toml {
            let merlinDir = dir.appendingPathComponent(".merlin")
            try FileManager.default.createDirectory(
                at: merlinDir, withIntermediateDirectories: true)
            try toml.write(to: merlinDir.appendingPathComponent("project.toml"),
                           atomically: true, encoding: .utf8)
        }
        return dir
    }

    func testWantsGateWhenPreCommitLayerPresent() async throws {
        let proj = try makeProject(toml: """
        adapter = "swift-xcode"
        adapter_version = "1.0"
        discipline_layers = ["soft_prompt", "pre_commit"]
        manual_coverage_baseline = 0
        decay_per_release = 10
        """)
        defer { try? FileManager.default.removeItem(at: proj) }

        let wants = await DisciplineGateInstaller.wantsPreCommitGate(projectPath: proj.path)
        XCTAssertTrue(wants, "a project opting into pre_commit must want the gate")
    }

    func testNoGateWhenPreCommitLayerAbsent() async throws {
        let proj = try makeProject(toml: """
        adapter = "swift-xcode"
        adapter_version = "1.0"
        discipline_layers = ["soft_prompt"]
        manual_coverage_baseline = 0
        decay_per_release = 10
        """)
        defer { try? FileManager.default.removeItem(at: proj) }

        let wants = await DisciplineGateInstaller.wantsPreCommitGate(projectPath: proj.path)
        XCTAssertFalse(wants, "a project without the pre_commit layer must not want the gate")
    }

    func testNoGateWhenNoProjectConfig() async throws {
        let proj = try makeProject(toml: nil)
        defer { try? FileManager.default.removeItem(at: proj) }

        let wants = await DisciplineGateInstaller.wantsPreCommitGate(projectPath: proj.path)
        XCTAssertFalse(wants,
                       "an un-adopted project (no .merlin/project.toml) must not want the gate")
    }
}
```

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'
```
Expected: **BUILD FAILED** — `DisciplineGateInstaller` does not exist yet. This is a
compile-failure phase (`build-for-testing` is the correct verb).

## Commit
```
git add MerlinTests/Unit/DisciplineGateInstallerTests.swift phases/phase-313a-discipline-gate-autoinstall-tests.md
git commit -m "Phase 313a — Discipline gate auto-install tests (failing)"
```
