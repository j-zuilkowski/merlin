import XCTest
@testable import Merlin

final class TaskScannerTestExclusionTests: XCTestCase {

    private var projectRoot: URL!

    override func setUpWithError() throws {
        projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: projectRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let projectRoot {
            try? FileManager.default.removeItem(at: projectRoot)
        }
    }

    private func writeFile(_ relativePath: String, _ contents: String) throws {
        let url = projectRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func testPublicTestSymbolsAreNotFlaggedAsUndocumented() async throws {
        try writeFile("tasks/task-001b-x.md", """
        # Task 001b — X

        New surface introduced in task 001b:
          - `RealType` — a real production type.
        """)
        try writeFile("Merlin/Real.swift", """
        public struct RealType {}
        """)
        // A public symbol inside the test target. It must NOT be enumerated as a
        // production source declaration, so it must not produce an orange finding.
        try writeFile("MerlinTests/Unit/Foo.swift", """
        import XCTest
        public func testThing() {}
        """)

        let scanner = TaskScanner()
        let findings = await scanner.scan(projectPath: projectRoot.path)

        let orangeForTestSymbol = findings.contains { finding in
            finding.severity == .orange && finding.surface.contains("testThing")
        }
        XCTAssertFalse(orangeForTestSymbol,
                       "Symbols inside MerlinTests/ must be excluded from source enumeration")
    }
}
