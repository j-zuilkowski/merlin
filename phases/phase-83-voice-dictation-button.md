# Phase 83 — Voice Dictation: Microphone Button in ChatView

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 82 complete: ContextUsageTracker shown in ProviderHUD.

`VoiceDictationEngine.shared` exists but is never connected to the UI. Add a microphone
button to `ChatView`'s `inputBar`. When tapped, toggles recording; on transcript, appends
text to `model.draft`.

---

## Edit: Merlin/Views/ChatView.swift

Add to the `inputBar` HStack, before the send button:

```swift
            VoiceDictationButton(draft: $model.draft)
                .disabled(model.isSending)
```

Add the `VoiceDictationButton` view at the bottom of `ChatView.swift` (outside the main struct):

```swift
private struct VoiceDictationButton: View {
    @Binding var draft: String
    @StateObject private var engine = VoiceDictationEngine.shared

    var body: some View {
        Button {
            Task {
                await engine.setOnTranscript { [weak engine] text in
                    Task { @MainActor in
                        self.draft += (self.draft.isEmpty ? "" : " ") + text
                        if engine?.state == .recording {
                            await engine?.stop()
                        }
                    }
                }
                await engine.toggle()
            }
        } label: {
            Image(systemName: engine.state == .recording ? "mic.fill" : "mic")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 20, height: 20)
                .foregroundStyle(engine.state == .recording ? .red : .primary)
        }
        .buttonStyle(.bordered)
        .help(engine.state == .recording ? "Stop recording" : "Dictate")
    }
}
```

`@StateObject private var engine = VoiceDictationEngine.shared` requires that
`VoiceDictationEngine` is `ObservableObject` and its `shared` property is a reference type —
both are already the case.

Since `VoiceDictationEngine` is `@MainActor`, using `@StateObject` is correct. The
`setOnTranscript` callback is called from the Speech framework on an arbitrary queue, so the
`Task { @MainActor in ... }` wrapper is required.

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD SUCCEEDED`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Views/ChatView.swift
git commit -m "Phase 83 — VoiceDictationButton added to ChatView inputBar; appends transcript to draft"
```
