import XCTest
@testable import Merlin

final class ContextInjectionTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ctx-inject-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    // MARK: - @mention resolution

    func testAtMentionIsReplacedWithFileContent() throws {
        let file = tmpDir.appendingPathComponent("hello.swift")
        try "func hello() {}".write(to: file, atomically: true, encoding: .utf8)

        let input = "Check out @hello.swift for context"
        let result = ContextInjector.resolveAtMentions(in: input, projectPath: tmpDir.path)

        XCTAssertTrue(result.contains("[File: hello.swift]"))
        XCTAssertTrue(result.contains("func hello() {}"))
        XCTAssertFalse(result.contains("@hello.swift"))
    }

    func testAtMentionWithLineRangeExtractsCorrectLines() throws {
        let lines = (1...10).map { "line\($0)" }.joined(separator: "\n")
        let file = tmpDir.appendingPathComponent("multi.swift")
        try lines.write(to: file, atomically: true, encoding: .utf8)

        let input = "@multi.swift:3-5"
        let result = ContextInjector.resolveAtMentions(in: input, projectPath: tmpDir.path)

        XCTAssertTrue(result.contains("line3"))
        XCTAssertTrue(result.contains("line4"))
        XCTAssertTrue(result.contains("line5"))
        XCTAssertFalse(result.contains("line1"))
        XCTAssertFalse(result.contains("line6"))
    }

    func testAtMentionFileTruncatedAt2000Lines() throws {
        let bigContent = (1...3000).map { "line\($0)" }.joined(separator: "\n")
        let file = tmpDir.appendingPathComponent("big.swift")
        try bigContent.write(to: file, atomically: true, encoding: .utf8)

        let result = ContextInjector.resolveAtMentions(in: "@big.swift", projectPath: tmpDir.path)

        XCTAssertTrue(result.contains("[File: big.swift]"))
        XCTAssertFalse(result.contains("line2001"),
                       "Files must be truncated at 2,000 lines")
        XCTAssertTrue(result.contains("[truncated]") || result.contains("truncated"),
                      "Truncated output must indicate truncation")
    }

    func testMissingFileAtMentionIsLeftUnchanged() {
        let input = "Look at @nonexistent.swift please"
        let result = ContextInjector.resolveAtMentions(in: input, projectPath: tmpDir.path)
        XCTAssertTrue(result.contains("@nonexistent.swift"),
                      "Unknown @mentions must be left in place")
    }

    func testNonAtMentionTextIsUnchanged() {
        let input = "Just a regular message with no mentions."
        let result = ContextInjector.resolveAtMentions(in: input, projectPath: tmpDir.path)
        XCTAssertEqual(result, input)
    }

    // MARK: - Attachment

    func testSwiftFileAttachmentInlined() async throws {
        let file = tmpDir.appendingPathComponent("Foo.swift")
        try "struct Foo {}".write(to: file, atomically: true, encoding: .utf8)

        let result = try await ContextInjector.inlineAttachment(url: file)

        XCTAssertTrue(result.contains("[File: Foo.swift]"))
        XCTAssertTrue(result.contains("struct Foo {}"))
    }

    func testUnsupportedBinaryTypeThrows() async {
        let file = tmpDir.appendingPathComponent("data.bin")
        try? Data([0x00, 0xFF, 0xFE]).write(to: file)

        do {
            _ = try await ContextInjector.inlineAttachment(url: file)
            XCTFail("Expected AttachmentError.unsupportedType")
        } catch AttachmentError.unsupportedType {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testMarkdownFileAttachmentInlined() async throws {
        let file = tmpDir.appendingPathComponent("README.md")
        try "# Hello".write(to: file, atomically: true, encoding: .utf8)
        let result = try await ContextInjector.inlineAttachment(url: file)
        XCTAssertTrue(result.contains("[File: README.md]"))
        XCTAssertTrue(result.contains("# Hello"))
    }
}
