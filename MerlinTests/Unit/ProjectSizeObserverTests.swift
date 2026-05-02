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
