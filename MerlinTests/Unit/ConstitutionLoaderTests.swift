import XCTest
@testable import Merlin

final class ConstitutionLoaderTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("merlin-claudemd-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    // MARK: - No files

    func testReturnsEmptyWhenNoFilesExist() {
        let content = ConstitutionLoader.load(projectPath: tmpDir.path, globalHome: nil)
        XCTAssertTrue(content.isEmpty)
    }

    // MARK: - Project root constitution.md

    func testFindsFileAtProjectRoot() throws {
        let fileURL = tmpDir.appendingPathComponent("constitution.md")
        try "# Project instructions".write(to: fileURL, atomically: true, encoding: .utf8)
        let content = ConstitutionLoader.load(projectPath: tmpDir.path, globalHome: nil)
        XCTAssertTrue(content.contains("Project instructions"))
    }

    // MARK: - .merlin/constitution.md

    func testFindsDotMerlinSubdirectory() throws {
        let subdir = tmpDir.appendingPathComponent(".merlin")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        let fileURL = subdir.appendingPathComponent("constitution.md")
        try "dotmerlin instructions".write(to: fileURL, atomically: true, encoding: .utf8)
        let content = ConstitutionLoader.load(projectPath: tmpDir.path, globalHome: nil)
        XCTAssertTrue(content.contains("dotmerlin instructions"))
    }

    // MARK: - Concatenation order

    func testProjectRootAppearsBeforeDotMerlin() throws {
        let rootURL = tmpDir.appendingPathComponent("constitution.md")
        try "ROOT".write(to: rootURL, atomically: true, encoding: .utf8)
        let subdir = tmpDir.appendingPathComponent(".merlin")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try "DOTMERLIN".write(to: subdir.appendingPathComponent("constitution.md"),
                              atomically: true, encoding: .utf8)
        let content = ConstitutionLoader.load(projectPath: tmpDir.path, globalHome: nil)
        let rootIdx = content.range(of: "ROOT")!.lowerBound
        let dotIdx  = content.range(of: "DOTMERLIN")!.lowerBound
        XCTAssertLessThan(rootIdx, dotIdx, "Project root constitution.md must appear before .merlin/constitution.md")
    }

    func testGlobalHomeAppendedLast() throws {
        let rootURL = tmpDir.appendingPathComponent("constitution.md")
        try "PROJECT".write(to: rootURL, atomically: true, encoding: .utf8)

        let globalDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("global-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: globalDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: globalDir) }
        try "GLOBAL".write(to: globalDir.appendingPathComponent("constitution.md"),
                           atomically: true, encoding: .utf8)

        let content = ConstitutionLoader.load(projectPath: tmpDir.path, globalHome: globalDir.path)
        let projIdx   = content.range(of: "PROJECT")!.lowerBound
        let globalIdx = content.range(of: "GLOBAL")!.lowerBound
        XCTAssertLessThan(projIdx, globalIdx, "Project instructions must appear before global constitution.md")
    }

    // MARK: - System prompt wrapping

    func testSystemPromptBlockWrapsContent() throws {
        let fileURL = tmpDir.appendingPathComponent("constitution.md")
        try "do the thing".write(to: fileURL, atomically: true, encoding: .utf8)
        let block = ConstitutionLoader.systemPromptBlock(projectPath: tmpDir.path, globalHome: nil)
        XCTAssertTrue(block.contains("[Project instructions]") || block.contains("Project instructions"),
                      "Block must include a [Project instructions] header")
        XCTAssertTrue(block.contains("do the thing"))
    }

    func testSystemPromptBlockIsEmptyWhenNoFiles() {
        let block = ConstitutionLoader.systemPromptBlock(projectPath: tmpDir.path, globalHome: nil)
        XCTAssertTrue(block.isEmpty)
    }
}
