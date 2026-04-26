import XCTest
@testable import Merlin

final class SessionSerializationTests: XCTestCase {
    var tmp: URL!

    override func setUp() {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testSessionRoundTrip() throws {
        let session = Session(
            title: "Test",
            messages: [Message(role: .user, content: .text("hi"), timestamp: Date())]
        )
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(Session.self, from: data)
        XCTAssertEqual(decoded.id, session.id)
        XCTAssertEqual(decoded.messages.count, 1)
    }

    func testTitleGeneration() {
        let msgs = [
            Message(
                role: .user,
                content: .text("How do I fix this crash in AppDelegate?"),
                timestamp: Date()
            )
        ]
        let title = Session.generateTitle(from: msgs)
        XCTAssertTrue(title.contains("How do I fix"))
    }

    func testTitleDefaultsForEmpty() {
        XCTAssertEqual(Session.generateTitle(from: []), "New Session")
    }

    @MainActor
    func testStoreSavesAndLoads() async throws {
        let store = SessionStore(storeDirectory: tmp)
        var session = store.create()
        session.messages.append(Message(role: .user, content: .text("hello"), timestamp: Date()))

        try store.save(session)

        let loaded = try store.load(id: session.id)
        XCTAssertEqual(loaded.messages.count, 1)
        if case .text(let text)? = loaded.messages.first?.content {
            XCTAssertEqual(text, "hello")
        } else {
            XCTFail("expected text content")
        }
    }
}
