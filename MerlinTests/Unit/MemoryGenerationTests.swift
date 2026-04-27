import XCTest
@testable import Merlin

final class MemoryGenerationTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("memory-gen-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - generateMemories

    func testGenerateMemoriesReturnsParsedEntries() async throws {
        let engine = MemoryEngine()
        let mock = MockProvider()
        mock.stubbedResponse = """
        - User prefers bullet points over paragraphs
        - Always run tests before committing
        - Project uses SWIFT_STRICT_CONCURRENCY=complete
        """
        await engine.setProvider(mock)

        let messages = [
            Message(role: .user, content: .text("How do I run tests?"), timestamp: Date()),
            Message(role: .assistant, content: .text("Use xcodebuild -scheme MerlinTests test"), timestamp: Date())
        ]

        let entries = try await engine.generateMemories(from: messages)
        XCTAssertEqual(entries.count, 3)
        XCTAssertTrue(entries[0].content.contains("bullet points"))
        XCTAssertTrue(entries[1].content.contains("run tests"))
    }

    func testGenerateMemoriesIgnoresSystemMessages() async throws {
        let engine = MemoryEngine()
        let mock = MockProvider()
        mock.stubbedResponse = "- Prefers dark mode"
        await engine.setProvider(mock)

        let messages = [
            Message(role: .system, content: .text("[Project instructions]\n..."), timestamp: Date()),
            Message(role: .user, content: .text("What theme do you recommend?"), timestamp: Date()),
            Message(role: .assistant, content: .text("Dark mode."), timestamp: Date())
        ]

        let entries = try await engine.generateMemories(from: messages)
        XCTAssertFalse(entries.isEmpty)
    }

    func testGenerateMemoriesEmptyTranscriptReturnsEmpty() async throws {
        let engine = MemoryEngine()
        let mock = MockProvider()
        mock.stubbedResponse = ""
        await engine.setProvider(mock)

        let entries = try await engine.generateMemories(from: [])
        XCTAssertTrue(entries.isEmpty)
    }

    func testGenerateMemoriesOnlySystemReturnsEmpty() async throws {
        let engine = MemoryEngine()
        let mock = MockProvider()
        mock.stubbedResponse = "- something"
        await engine.setProvider(mock)

        let messages = [
            Message(role: .system, content: .text("system prompt"), timestamp: Date())
        ]
        let entries = try await engine.generateMemories(from: messages)
        XCTAssertTrue(entries.isEmpty, "Only system messages should produce no entries")
    }

    func testGenerateMemoriesFilenamesAreUUIDs() async throws {
        let engine = MemoryEngine()
        let mock = MockProvider()
        mock.stubbedResponse = "- User likes concise answers"
        await engine.setProvider(mock)

        let messages = [Message(role: .user, content: .text("hi"), timestamp: Date())]
        let entries = try await engine.generateMemories(from: messages)
        for entry in entries {
            let nameWithoutExt = (entry.filename as NSString).deletingPathExtension
            XCTAssertNotNil(UUID(uuidString: nameWithoutExt), "Filename should be a UUID: \(entry.filename)")
            XCTAssertTrue(entry.filename.hasSuffix(".md"))
        }
    }

    func testGenerateMemoriesSanitizesSecrets() async throws {
        let engine = MemoryEngine()
        let mock = MockProvider()
        mock.stubbedResponse = "- Token sk-ant-abc123xyz is the key"
        await engine.setProvider(mock)

        let messages = [Message(role: .user, content: .text("hi"), timestamp: Date())]
        let entries = try await engine.generateMemories(from: messages)
        for entry in entries {
            XCTAssertFalse(entry.content.contains("sk-ant-abc123xyz"), "Secrets should be redacted")
        }
    }

    // MARK: - generateAndNotify

    func testGenerateAndNotifyWritesFilesToPendingDir() async throws {
        let engine = MemoryEngine()
        let mock = MockProvider()
        mock.stubbedResponse = "- User prefers TDD"
        await engine.setProvider(mock)

        let messages = [Message(role: .user, content: .text("test"), timestamp: Date())]
        let notificationEngine = NotificationEngine()

        try await engine.generateAndNotify(
            messages: messages,
            pendingDir: tempDir,
            notificationEngine: notificationEngine
        )

        let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        XCTAssertFalse(files.isEmpty, "At least one memory file should be written")
        XCTAssertTrue(files.allSatisfy { $0.pathExtension == "md" })
    }

    func testGenerateAndNotifyEmptyTranscriptWritesNothing() async throws {
        let engine = MemoryEngine()
        let mock = MockProvider()
        mock.stubbedResponse = ""
        await engine.setProvider(mock)

        let notificationEngine = NotificationEngine()
        try await engine.generateAndNotify(messages: [], pendingDir: tempDir, notificationEngine: notificationEngine)

        let files = (try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)) ?? []
        XCTAssertTrue(files.isEmpty)
    }
}
