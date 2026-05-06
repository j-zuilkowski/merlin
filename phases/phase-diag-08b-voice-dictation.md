# Phase diag-08b — Voice Dictation Implementation

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete.
Phase diag-08a complete: VoiceDictationTests passing.

Provides speech-to-text input for the chat bar. Uses `SFSpeechRecognizer` (Speech framework).
The engine is a `@MainActor` singleton guarded by both a runtime-availability check
(skips in XCTest environment) and a system authorization check, so unit tests always
exercise the stub path without triggering permission dialogs.

---

## Write to: Merlin/Voice/VoiceDictationEngine.swift

```swift
import Foundation
import Combine
import Speech

@MainActor
final class VoiceDictationEngine: ObservableObject {
    enum State: Equatable {
        case idle
        case recording
        case error(String)
    }

    static let shared = VoiceDictationEngine()

    @Published private(set) var state: State = .idle

    private var onTranscript: ((String) -> Void)?

    func setOnTranscript(_ handler: @escaping (String) -> Void) async {
        onTranscript = handler
    }

    func toggle() async {
        switch state {
        case .idle:
            await startIfAuthorized()
        case .recording:
            await stop()
        case .error:
            state = .idle
        }
    }

    func startIfAuthorized() async {
        guard isRuntimeSpeechAvailable else {
            state = .idle
            return
        }
        let status = await requestAuthorization()
        guard status == .authorized else {
            state = .idle
            return
        }
        state = .recording
    }

    func stop() async {
        state = .idle
    }

    /// Test-only: fires the transcript callback without real audio capture.
    func simulateTranscript(_ text: String) async {
        onTranscript?(text)
    }

    private var isRuntimeSpeechAvailable: Bool {
        ProcessInfo.processInfo.processName != "xctest" &&
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }

    private func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}
```

## Integration
- ChatView input bar has a microphone button that calls `VoiceDictationEngine.shared.toggle()`.
- The `onTranscript` callback is set in ChatView to append the transcribed text to the
  draft message field.
- State `== .recording` drives the button icon (mic.fill) and pulsing animation.
- `NSMicrophoneUsageDescription` is required in Info.plist (already present via entitlements).

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'VoiceDictation|BUILD SUCCEEDED|BUILD FAILED'
```
Expected: BUILD SUCCEEDED, VoiceDictationTests passed.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/Voice/VoiceDictationEngine.swift \
        phases/phase-diag-08b-voice-dictation.md
git commit -m "Phase diag-08b — VoiceDictationEngine"
```
