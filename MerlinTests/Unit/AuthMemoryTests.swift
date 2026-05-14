import XCTest
@testable import Merlin

final class AuthMemoryTests: XCTestCase {
    var tmp: URL!
    var memory: AuthMemory!

    override func setUp() {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        memory = AuthMemory(storePath: tmp.path)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testAllowPatternPersistedAndLoaded() throws {
        memory.addAllowPattern(tool: "read_file", pattern: "~/Projects/**")
        try memory.save()

        let loaded = AuthMemory(storePath: tmp.path)
        XCTAssertTrue(loaded.isAllowed(tool: "read_file",
                                       argument: "\(NSHomeDirectory())/Projects/Foo/bar.swift"))
    }

    func testSaveRestrictsAuthFilePermissionsToOwnerOnly() throws {
        memory.addAllowPattern(tool: "run_shell", pattern: "swift test")
        try memory.save()

        let attrs = try FileManager.default.attributesOfItem(atPath: tmp.path)
        let permissions = attrs[.posixPermissions] as? NSNumber

        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testDenyPatternBlocksMatch() throws {
        memory.addDenyPattern(tool: "run_shell", pattern: "rm -rf /**")
        XCTAssertTrue(memory.isDenied(tool: "run_shell", argument: "rm -rf /"))
    }

    func testNoMatchReturnsFalse() {
        XCTAssertFalse(memory.isAllowed(tool: "write_file", argument: "/etc/hosts"))
        XCTAssertFalse(memory.isDenied(tool: "write_file", argument: "/etc/hosts"))
    }
}
