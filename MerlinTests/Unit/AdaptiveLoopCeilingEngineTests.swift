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
