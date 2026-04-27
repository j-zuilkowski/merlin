import XCTest
@testable import Merlin

final class StagingBufferTests: XCTestCase {

    private func tempPath(_ name: String) -> String {
        "/tmp/staging-test-\(name)-\(UUID().uuidString).txt"
    }

    // MARK: - stage

    func testStageAppendsToPendingChanges() async {
        let buffer = StagingBuffer()
        let change = StagedChange(
            path: tempPath("a"),
            kind: .write,
            before: nil,
            after: "hello"
        )
        await buffer.stage(change)
        let pending = await buffer.pendingChanges
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.path, change.path)
    }

    func testStageMultipleChanges() async {
        let buffer = StagingBuffer()
        for i in 0..<5 {
            await buffer.stage(StagedChange(path: tempPath("\(i)"), kind: .write, before: nil, after: "x"))
        }
        let count = await buffer.pendingChanges.count
        XCTAssertEqual(count, 5)
    }

    // MARK: - accept

    func testAcceptWritesFileAndRemovesFromPending() async throws {
        let buffer = StagingBuffer()
        let path = tempPath("accept")
        let change = StagedChange(path: path, kind: .write, before: nil, after: "written content")
        await buffer.stage(change)

        try await buffer.accept(change.id)

        let content = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertEqual(content, "written content")

        let pending = await buffer.pendingChanges
        XCTAssertTrue(pending.isEmpty)

        try? FileManager.default.removeItem(atPath: path)
    }

    func testAcceptCreateWritesNewFile() async throws {
        let buffer = StagingBuffer()
        let path = tempPath("create")
        let change = StagedChange(path: path, kind: .create, before: nil, after: "new file")
        await buffer.stage(change)

        try await buffer.accept(change.id)

        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        try? FileManager.default.removeItem(atPath: path)
    }

    func testAcceptDeleteRemovesFile() async throws {
        let buffer = StagingBuffer()
        let path = tempPath("delete")
        try "existing".write(toFile: path, atomically: true, encoding: .utf8)

        let change = StagedChange(path: path, kind: .delete, before: "existing", after: nil)
        await buffer.stage(change)

        try await buffer.accept(change.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testAcceptUnknownIDIsNoop() async throws {
        let buffer = StagingBuffer()
        // Should not throw
        try await buffer.accept(UUID())
    }

    // MARK: - reject

    func testRejectRemovesFromPendingWithoutWriting() async throws {
        let buffer = StagingBuffer()
        let path = tempPath("reject")
        let change = StagedChange(path: path, kind: .write, before: nil, after: "should not write")
        await buffer.stage(change)

        await buffer.reject(change.id)

        let pending = await buffer.pendingChanges
        XCTAssertTrue(pending.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    // MARK: - acceptAll / rejectAll

    func testAcceptAllWritesAllFiles() async throws {
        let buffer = StagingBuffer()
        let paths = (0..<3).map { tempPath("all-\($0)") }
        for path in paths {
            await buffer.stage(StagedChange(path: path, kind: .write, before: nil, after: "x"))
        }

        try await buffer.acceptAll()

        let pending = await buffer.pendingChanges
        XCTAssertTrue(pending.isEmpty)
        for path in paths {
            XCTAssertTrue(FileManager.default.fileExists(atPath: path))
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    func testRejectAllClearsPendingWithoutWriting() async {
        let buffer = StagingBuffer()
        for i in 0..<3 {
            await buffer.stage(StagedChange(path: tempPath("ra-\(i)"), kind: .write, before: nil, after: "x"))
        }

        await buffer.rejectAll()

        let pending = await buffer.pendingChanges
        XCTAssertTrue(pending.isEmpty)
    }
}
