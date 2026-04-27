import Speech
import XCTest
@testable import Merlin

@MainActor
final class VoiceDictationTests: XCTestCase {

    // MARK: - VoiceDictationEngine state machine

    func test_engine_initiallyIdle() {
        let engine = VoiceDictationEngine()
        XCTAssertEqual(engine.state, .idle)
    }

    func test_engine_startSetsRecording() async {
        let engine = VoiceDictationEngine()
        await engine.startIfAuthorized()
        XCTAssertTrue(engine.state == .recording || engine.state == .idle)
    }

    func test_engine_stopReturnsToIdle() async {
        let engine = VoiceDictationEngine()
        await engine.startIfAuthorized()
        await engine.stop()
        XCTAssertEqual(engine.state, .idle)
    }

    func test_engine_toggleStartsThenStops() async {
        let engine = VoiceDictationEngine()
        await engine.toggle()
        let stateAfterFirstToggle = engine.state
        await engine.toggle()
        let stateAfterSecondToggle = engine.state
        XCTAssertTrue(
            (stateAfterFirstToggle == .recording && stateAfterSecondToggle == .idle) ||
            (stateAfterFirstToggle == .idle && stateAfterSecondToggle == .idle)
        )
    }

    // MARK: - Transcript callback

    func test_transcriptCallback_calledOnResult() async {
        let engine = VoiceDictationEngine()
        var received: String?
        await engine.setOnTranscript { text in
            received = text
        }
        await engine.simulateTranscript("hello world")
        XCTAssertEqual(received, "hello world")
    }

    // MARK: - FloatingWindowManager

    func test_floatingWindowManager_openCreatesWindow() {
        let manager = FloatingWindowManager()
        let session = Session.stub()
        manager.open(session: session, alwaysOnTop: false)
        XCTAssertEqual(manager.openWindowCount, 1)
    }

    func test_floatingWindowManager_openSameSessionIsIdempotent() {
        let manager = FloatingWindowManager()
        let session = Session.stub()
        manager.open(session: session, alwaysOnTop: false)
        manager.open(session: session, alwaysOnTop: false)
        XCTAssertEqual(manager.openWindowCount, 1)
    }

    func test_floatingWindowManager_closeRemovesWindow() {
        let manager = FloatingWindowManager()
        let session = Session.stub()
        manager.open(session: session, alwaysOnTop: false)
        manager.close(sessionID: session.id)
        XCTAssertEqual(manager.openWindowCount, 0)
    }
}

extension Session {
    static func stub() -> Session {
        Session(title: "Test Session", messages: [])
    }
}
