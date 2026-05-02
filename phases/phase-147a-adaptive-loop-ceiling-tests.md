# Phase 147a — Adaptive Loop Ceiling Tests (failing)

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 146b complete: provider settings UI with dynamic model picker.

New surface introduced in phase 147b:
  - `ProjectSizeMetrics` — value type holding `sourceFileCount: Int` and
    `adaptiveCeiling(for: ComplexityTier) -> Int`. Formula:
    `clamp(10 + floor(log2(sourceFileCount + 1)) * 4, 10, 80)` × tier multiplier
    (routine ×0.6, standard ×1.0, high-stakes ×1.5), result clamped to [10, 80].
    Static `default` property (sourceFileCount = 0) returns 10 for all tiers.
  - `ProjectSizeObserver` — actor with `observe(path: String) async -> ProjectSizeMetrics`.
    Counts files whose extension is in a curated source-extensions set. Ignores
    subdirectories named `.git`, `.build`, `DerivedData`, `node_modules`, `.swiftpm`,
    `Pods`, `Carthage`, `__pycache__`, `venv`, `.venv`, `dist`, `target`, `.next`.
    Returns `.default` when path is empty or does not exist.
  - `AgenticEngine.projectSizeMetrics: ProjectSizeMetrics` — updated whenever
    `currentProjectPath` changes (via a background Task). `effectiveLoopCeiling` in
    `runLoop` becomes `max(projectSizeMetrics.adaptiveCeiling(for: complexity),
    AppSettings.shared.maxLoopIterations)`.

TDD coverage:
  File 1 — ProjectSizeMetricsTests: ceiling formula, tier multipliers, clamp bounds
  File 2 — ProjectSizeObserverTests: file counting, extension filtering, dir exclusion
  File 3 — AdaptiveLoopCeilingEngineTests: engine wires metrics, ceiling > default when project set

---

## Write to: MerlinTests/Unit/ProjectSizeMetricsTests.swift

```swift
import XCTest
@testable import Merlin

final class ProjectSizeMetricsTests: XCTestCase {

    // MARK: - Default

    func testDefaultReturnsMinimumCeiling() {
        let m = ProjectSizeMetrics.default
        XCTAssertEqual(m.adaptiveCeiling(for: .routine),    10)
        XCTAssertEqual(m.adaptiveCeiling(for: .standard),   10)
        XCTAssertEqual(m.adaptiveCeiling(for: .highStakes), 10)
    }

    // MARK: - Formula: standard tier

    func testSingleFileMeetsMinimum() {
        let m = ProjectSizeMetrics(sourceFileCount: 1)
        // log2(2)*4 = 4 → 10+4=14; standard × 1.0 = 14
        XCTAssertGreaterThanOrEqual(m.adaptiveCeiling(for: .standard), 10)
    }

    func testSmallProject() {
        // 10 files: floor(log2(11))*4 = 3*4=12 → 10+12=22
        let m = ProjectSizeMetrics(sourceFileCount: 10)
        XCTAssertEqual(m.adaptiveCeiling(for: .standard), 22)
    }

    func testMediumProject() {
        // 100 files: floor(log2(101))*4 = 6*4=24 → 10+24=34
        let m = ProjectSizeMetrics(sourceFileCount: 100)
        XCTAssertEqual(m.adaptiveCeiling(for: .standard), 34)
    }

    func testLargeProject() {
        // 5000 files: floor(log2(5001))*4 = 12*4=48 → 10+48=58
        let m = ProjectSizeMetrics(sourceFileCount: 5000)
        XCTAssertEqual(m.adaptiveCeiling(for: .standard), 58)
    }

    func testVeryLargeProjectCapsAt80() {
        // 1_000_000 files would exceed cap
        let m = ProjectSizeMetrics(sourceFileCount: 1_000_000)
        XCTAssertEqual(m.adaptiveCeiling(for: .standard), 80)
    }

    // MARK: - Tier multipliers

    func testRoutineTierIsLowerThanStandard() {
        let m = ProjectSizeMetrics(sourceFileCount: 500)
        let routine  = m.adaptiveCeiling(for: .routine)
        let standard = m.adaptiveCeiling(for: .standard)
        XCTAssertLessThanOrEqual(routine, standard)
    }

    func testHighStakesTierIsHigherThanStandard() {
        let m = ProjectSizeMetrics(sourceFileCount: 100)
        let standard   = m.adaptiveCeiling(for: .standard)
        let highStakes = m.adaptiveCeiling(for: .highStakes)
        XCTAssertGreaterThanOrEqual(highStakes, standard)
    }

    func testRoutineNeverFallsBelowMinimum() {
        // Even with zero files, routine must be ≥ 10
        let m = ProjectSizeMetrics(sourceFileCount: 0)
        XCTAssertGreaterThanOrEqual(m.adaptiveCeiling(for: .routine), 10)
    }

    func testHighStakesNeverExceedsMaximum() {
        let m = ProjectSizeMetrics(sourceFileCount: 999_999)
        XCTAssertLessThanOrEqual(m.adaptiveCeiling(for: .highStakes), 80)
    }

    // MARK: - Monotonicity

    func testCeilingIncreasesWithFileCount() {
        let small  = ProjectSizeMetrics(sourceFileCount: 10).adaptiveCeiling(for: .standard)
        let medium = ProjectSizeMetrics(sourceFileCount: 100).adaptiveCeiling(for: .standard)
        let large  = ProjectSizeMetrics(sourceFileCount: 1000).adaptiveCeiling(for: .standard)
        XCTAssertLessThanOrEqual(small, medium)
        XCTAssertLessThanOrEqual(medium, large)
    }
}
```

---

## Write to: MerlinTests/Unit/ProjectSizeObserverTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class ProjectSizeObserverTests: XCTestCase {

    private var tmpDir: URL!
    private let observer = ProjectSizeObserver()

    override func setUp() async throws {
        try await super.setUp()
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("merlin-pso-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func touch(_ name: String, in dir: URL? = nil) throws {
        let parent = dir ?? tmpDir!
        try "".write(to: parent.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func mkdir(_ name: String, in dir: URL? = nil) throws -> URL {
        let parent = dir ?? tmpDir!
        let url = parent.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Empty / missing path

    func testEmptyPathReturnsDefault() async {
        let m = await observer.observe(path: "")
        XCTAssertEqual(m.sourceFileCount, 0)
        XCTAssertEqual(m.adaptiveCeiling(for: .standard), 10)
    }

    func testNonexistentPathReturnsDefault() async {
        let m = await observer.observe(path: "/tmp/does-not-exist-\(UUID().uuidString)")
        XCTAssertEqual(m.sourceFileCount, 0)
    }

    // MARK: - Source file counting

    func testCountsSwiftFiles() async throws {
        try touch("Foo.swift")
        try touch("Bar.swift")
        try touch("Baz.swift")
        let m = await observer.observe(path: tmpDir.path)
        XCTAssertEqual(m.sourceFileCount, 3)
    }

    func testCountsPythonFiles() async throws {
        try touch("main.py")
        try touch("utils.py")
        let m = await observer.observe(path: tmpDir.path)
        XCTAssertEqual(m.sourceFileCount, 2)
    }

    func testIgnoresNonSourceFiles() async throws {
        try touch("icon.png")
        try touch("README.md")
        try touch("data.json")
        try touch("Makefile")
        let m = await observer.observe(path: tmpDir.path)
        XCTAssertEqual(m.sourceFileCount, 0,
                       "PNG, Markdown, JSON, and Makefile must not count as source files")
    }

    func testCountsMixedExtensions() async throws {
        try touch("App.swift")
        try touch("server.py")
        try touch("index.ts")
        try touch("logo.png")   // ignored
        try touch("notes.md")   // ignored
        let m = await observer.observe(path: tmpDir.path)
        XCTAssertEqual(m.sourceFileCount, 3)
    }

    // MARK: - Directory exclusion

    func testIgnoresDotGit() async throws {
        let git = try mkdir(".git")
        try touch("HEAD", in: git)
        try touch("config", in: git)
        try touch("hidden.swift", in: git)
        try touch("real.swift")
        let m = await observer.observe(path: tmpDir.path)
        XCTAssertEqual(m.sourceFileCount, 1, ".git contents must be excluded")
    }

    func testIgnoresNodeModules() async throws {
        let nm = try mkdir("node_modules")
        try touch("index.js", in: nm)
        try touch("util.ts", in: nm)
        try touch("app.ts")
        let m = await observer.observe(path: tmpDir.path)
        XCTAssertEqual(m.sourceFileCount, 1, "node_modules must be excluded")
    }

    func testIgnoresDerivedData() async throws {
        let dd = try mkdir("DerivedData")
        try touch("main.swift", in: dd)
        try touch("real.swift")
        let m = await observer.observe(path: tmpDir.path)
        XCTAssertEqual(m.sourceFileCount, 1, "DerivedData must be excluded")
    }

    func testIgnoresDotBuild() async throws {
        let build = try mkdir(".build")
        try touch("main.swift", in: build)
        try touch("real.swift")
        let m = await observer.observe(path: tmpDir.path)
        XCTAssertEqual(m.sourceFileCount, 1, ".build must be excluded")
    }

    func testIgnoresPythonVenv() async throws {
        let venv = try mkdir("venv")
        try touch("activate.py", in: venv)
        try touch("app.py")
        let m = await observer.observe(path: tmpDir.path)
        XCTAssertEqual(m.sourceFileCount, 1, "venv must be excluded")
    }

    func testCountsNestedSourceFiles() async throws {
        let sub = try mkdir("Sources")
        let deep = try mkdir("Core", in: sub)
        try touch("Engine.swift", in: sub)
        try touch("Model.swift", in: deep)
        try touch("main.swift")
        let m = await observer.observe(path: tmpDir.path)
        XCTAssertEqual(m.sourceFileCount, 3, "Recursive subdirectories must be counted")
    }

    // MARK: - Ceiling reflects count

    func testObservedCeilingExceedsDefaultForManyFiles() async throws {
        for i in 0..<50 {
            try touch("File\(i).swift")
        }
        let m = await observer.observe(path: tmpDir.path)
        XCTAssertGreaterThan(m.adaptiveCeiling(for: .standard), 10,
                             "50 source files should produce a ceiling above the 10-iteration default")
    }
}
```

---

## Write to: MerlinTests/Unit/AdaptiveLoopCeilingEngineTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class AdaptiveLoopCeilingEngineTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("merlin-loop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
        try await super.tearDown()
    }

    // MARK: - Default (no project path)

    func testDefaultMetricsWhenNoProjectPath() {
        let engine = makeEngine()
        engine.currentProjectPath = nil
        XCTAssertEqual(engine.projectSizeMetrics.sourceFileCount, 0)
    }

    // MARK: - Metrics update when path set

    func testMetricsUpdateAfterProjectPathSet() async throws {
        // Seed 30 Swift files
        for i in 0..<30 {
            try "".write(to: tmpDir.appendingPathComponent("F\(i).swift"),
                         atomically: true, encoding: .utf8)
        }
        let engine = makeEngine()
        engine.currentProjectPath = tmpDir.path

        // Yield to allow the background scan task to finish
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(engine.projectSizeMetrics.sourceFileCount, 30)
    }

    // MARK: - effectiveLoopCeiling

    func testEffectiveCeilingIsMaxOfAdaptiveAndSettings() async throws {
        for i in 0..<30 {
            try "".write(to: tmpDir.appendingPathComponent("F\(i).swift"),
                         atomically: true, encoding: .utf8)
        }
        let engine = makeEngine()
        let savedMax = AppSettings.shared.maxLoopIterations
        defer { AppSettings.shared.maxLoopIterations = savedMax }
        AppSettings.shared.maxLoopIterations = 5   // below adaptive

        engine.currentProjectPath = tmpDir.path
        try await Task.sleep(for: .milliseconds(200))

        // adaptive for 30 files, standard tier:
        // floor(log2(31))*4 = 4*4=16 → 10+16=26
        // max(26, 5) = 26
        XCTAssertGreaterThan(engine.effectiveLoopCeiling(for: .standard), 5,
                             "Adaptive ceiling must override settings value when it is higher")
    }

    func testEffectiveCeilingRespectsHigherSettingsValue() {
        let engine = makeEngine()
        let savedMax = AppSettings.shared.maxLoopIterations
        defer { AppSettings.shared.maxLoopIterations = savedMax }
        AppSettings.shared.maxLoopIterations = 60   // above adaptive for empty project

        XCTAssertEqual(engine.effectiveLoopCeiling(for: .standard), 60,
                       "Settings value must win when it exceeds the adaptive ceiling")
    }
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD FAILED — `ProjectSizeMetrics`, `ProjectSizeObserver`, and
`engine.effectiveLoopCeiling(for:)` not yet defined.

## Commit
```bash
git add MerlinTests/Unit/ProjectSizeMetricsTests.swift \
        MerlinTests/Unit/ProjectSizeObserverTests.swift \
        MerlinTests/Unit/AdaptiveLoopCeilingEngineTests.swift
git commit -m "Phase 147a — Adaptive loop ceiling tests (failing)"
```
