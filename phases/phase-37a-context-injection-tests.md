# Phase 37a — Context Injection Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 36b complete: CLAUDEMDLoader + engine integration.

New surface introduced in phase 37b:
  - `ContextInjector.resolveAtMentions(in:projectPath:) -> String`
    Replaces `@filename` and `@filename:start-end` tokens with `[File: name]\n<content>\n`
    blocks. Paths are resolved relative to projectPath. Files truncated at 2,000 lines;
    line-range syntax limits to the specified range.
  - `ContextInjector.inlineAttachment(url:) async throws -> String`
    Source files (.swift, .md, .json, .txt, etc.): returns `[File: name]\n<content>\n`
    Images (.png, .jpg, .heic): returns `[Image: name — vision analysis pending]\n`
    PDFs (.pdf): extracts text via PDFKit, returns `[PDF: name]\n<text>\n`
    Binary/other: throws `AttachmentError.unsupportedType`
  - `AttachmentError` — enum: unsupportedType, readFailed

TDD coverage:
  File 1 — ContextInjectionTests: @mention replacement; line range syntax; missing file
            returns unchanged token; PDF text extraction; unsupported type throws

---

## Write to: MerlinTests/Unit/ContextInjectionTests.swift

```swift
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
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD FAILED` with errors referencing `ContextInjector`, `AttachmentError`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/ContextInjectionTests.swift
git commit -m "Phase 37a — ContextInjectionTests (failing)"
```
