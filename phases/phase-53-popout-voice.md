# Phase 53 — Floating Pop-out Window + Voice Dictation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 52 complete: Toolbar Actions + Notifications in place.

Two features:
1. **Floating pop-out window** — detach any session thread into a standalone floating window;
   optional always-on-top mode
2. **Voice dictation** — Ctrl+M to toggle microphone recording; transcribed text is inserted
   into the prompt composer via `SFSpeechRecognizer`

No a/b split. Tests in `MerlinTests/Unit/VoiceDictationTests.swift`.

---

## Tests: MerlinTests/Unit/VoiceDictationTests.swift

```swift
import XCTest
import Speech
@testable import Merlin

final class VoiceDictationTests: XCTestCase {

    // MARK: - VoiceDictationEngine state machine

    func test_engine_initiallyIdle() {
        let engine = VoiceDictationEngine()
        XCTAssertEqual(engine.state, .idle)
    }

    func test_engine_startSetsRecording() async {
        let engine = VoiceDictationEngine()
        // If authorization is not granted (CI/test environment), start() returns without crash
        await engine.startIfAuthorized()
        // State is either .recording or .idle (if not authorized) — never .error after start()
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
        // Either started (recording) then stopped (idle), or both idle if not authorized
        XCTAssertTrue(
            (stateAfterFirstToggle == .recording && stateAfterSecondToggle == .idle) ||
            (stateAfterFirstToggle == .idle && stateAfterSecondToggle == .idle)
        )
    }

    // MARK: - Transcript callback

    func test_transcriptCallback_calledOnResult() async {
        let engine = VoiceDictationEngine()
        var received: String?
        await engine.setOnTranscript { text in received = text }
        // Simulate a transcript result directly
        await engine.simulateTranscript("hello world")
        XCTAssertEqual(received, "hello world")
    }

    // MARK: - FloatingWindowManager

    func test_floatingWindowManager_openCreatesWindow() {
        let manager = FloatingWindowManager()
        let session = ChatSession.stub()
        manager.open(session: session, alwaysOnTop: false)
        XCTAssertEqual(manager.openWindowCount, 1)
    }

    func test_floatingWindowManager_openSameSessionIsIdempotent() {
        let manager = FloatingWindowManager()
        let session = ChatSession.stub()
        manager.open(session: session, alwaysOnTop: false)
        manager.open(session: session, alwaysOnTop: false)
        XCTAssertEqual(manager.openWindowCount, 1)
    }

    func test_floatingWindowManager_closeRemovesWindow() {
        let manager = FloatingWindowManager()
        let session = ChatSession.stub()
        manager.open(session: session, alwaysOnTop: false)
        manager.close(sessionID: session.id)
        XCTAssertEqual(manager.openWindowCount, 0)
    }
}

// MARK: - ChatSession stub for tests

extension ChatSession {
    static func stub() -> ChatSession {
        ChatSession(id: UUID(), title: "Test Session", messages: [])
    }
}
```

---

## New files

### Merlin/Voice/VoiceDictationEngine.swift

```swift
import Foundation
import Speech
import AVFoundation

// Manages speech recognition for voice dictation (Ctrl+M toggle).
@MainActor
final class VoiceDictationEngine: ObservableObject {

    enum State: Equatable {
        case idle, recording, error(String)
    }

    @Published private(set) var state: State = .idle
    private var onTranscript: ((String) -> Void)?

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // MARK: - Public API

    func setOnTranscript(_ handler: @escaping (String) -> Void) {
        onTranscript = handler
    }

    func toggle() async {
        switch state {
        case .idle:    await startIfAuthorized()
        case .recording: await stop()
        case .error:   state = .idle
        }
    }

    func startIfAuthorized() async {
        let status = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard status == .authorized else { return }
        do {
            try startRecognition()
            state = .recording
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func stop() async {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        state = .idle
    }

    // Test helper: inject a transcript result directly.
    func simulateTranscript(_ text: String) {
        onTranscript?(text)
    }

    // MARK: - Recognition

    private func startRecognition() throws {
        recognizer = SFSpeechRecognizer(locale: Locale.current)
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognizer, let recognitionRequest else {
            throw VoiceDictationError.recognizerUnavailable
        }
        recognitionRequest.shouldReportPartialResults = false

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            if let result, result.isFinal {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in
                    self.onTranscript?(text)
                    await self.stop()
                }
            }
            if let error {
                Task { @MainActor in
                    self.state = .error(error.localizedDescription)
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }
}

enum VoiceDictationError: Error, LocalizedError {
    case recognizerUnavailable
    var errorDescription: String? { "Speech recognizer unavailable" }
}
```

### Merlin/Windows/FloatingWindowManager.swift

```swift
import AppKit
import SwiftUI

// Manages floating pop-out windows for detached chat sessions.
// Each session can have at most one floating window.
@MainActor
final class FloatingWindowManager: ObservableObject {

    private var windows: [UUID: NSWindow] = [:]

    var openWindowCount: Int { windows.count }

    func open(session: ChatSession, alwaysOnTop: Bool) {
        guard windows[session.id] == nil else {
            windows[session.id]?.makeKeyAndOrderFront(nil)
            return
        }
        let view = FloatingChatView(session: session, manager: self)
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 480, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = session.title
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        if alwaysOnTop {
            window.level = .floating
        }
        window.center()
        window.makeKeyAndOrderFront(nil)

        // Track via delegate so we can remove from dictionary on close
        let tracker = WindowCloseTracker(sessionID: session.id, manager: self)
        window.delegate = tracker
        objc_setAssociatedObject(window, &FloatingWindowManager.trackerKey, tracker, .OBJC_ASSOCIATION_RETAIN)

        windows[session.id] = window
    }

    func close(sessionID: UUID) {
        windows[sessionID]?.close()
        windows.removeValue(forKey: sessionID)
    }

    private static var trackerKey: UInt8 = 0
}

// Delegates window close events back to FloatingWindowManager
private final class WindowCloseTracker: NSObject, NSWindowDelegate, Sendable {
    private let sessionID: UUID
    private weak var manager: FloatingWindowManager?

    init(sessionID: UUID, manager: FloatingWindowManager) {
        self.sessionID = sessionID
        self.manager = manager
    }

    func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            self.manager?.windows.removeValue(forKey: self.sessionID)
        }
    }
}

// Minimal floating chat view — renders existing ChatView with close button
struct FloatingChatView: View {
    let session: ChatSession
    let manager: FloatingWindowManager

    var body: some View {
        VStack(spacing: 0) {
            ChatView(session: session)
            HStack {
                Spacer()
                Button("Close") {
                    manager.close(sessionID: session.id)
                }
                .padding(8)
            }
        }
    }
}
```

---

## Integration: Voice dictation keyboard shortcut

In `MerlinCommands` (or a `.focusedObject` binding on ChatView), add Ctrl+M:

```swift
Button("Toggle Dictation") {
    Task { await dictationEngine.toggle() }
}
.keyboardShortcut("m", modifiers: .control)
```

Wire `dictationEngine.setOnTranscript` to append text to the prompt composer's `@State var draft`.

---

## Integration: Pop-out window menu item

In the session context menu or View menu:

```swift
Button("Pop out to Window") {
    FloatingWindowManager.shared.open(session: currentSession, alwaysOnTop: false)
}
Button("Pop out (Always on Top)") {
    FloatingWindowManager.shared.open(session: currentSession, alwaysOnTop: true)
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED, all VoiceDictationTests pass.

## Commit
```bash
git add MerlinTests/Unit/VoiceDictationTests.swift \
        Merlin/Voice/VoiceDictationEngine.swift \
        Merlin/Windows/FloatingWindowManager.swift
git commit -m "Phase 53 — Floating pop-out window + voice dictation (Ctrl+M)"
```
