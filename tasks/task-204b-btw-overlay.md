# Task 204b — /btw Side-Question Overlay

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 204a complete: failing BtwSessionTests.

`/btw` opens a floating overlay that sends a one-shot question directly to the active provider.
The response is shown in the overlay. Nothing is written to `ContextManager` or the conversation
history. The overlay is dismissed by pressing Esc or clicking outside it.

---

## Edit: TestHelpers/MockProvider.swift

Add a `response: String` parameter and optional `delay: TimeInterval` parameter:

```swift
init(
    response:          String = "mock response",
    delay:             TimeInterval = 0,
    shouldFail:        Bool = false,
    failFirstCallWith: ProviderError? = nil,
    failAllCallsWith:  ProviderError? = nil
) { ... }
```

When `delay > 0`, call `try await Task.sleep(for: .seconds(delay))` before yielding the response
token. This allows `test_isLoading_true_during_ask` to observe the loading state.

The `response` string should be yielded as a single streaming chunk (or multiple chunks — whichever
matches how the real provider streaming works). Adapt to `MockProvider`'s existing streaming pattern.

---

## Write to: Merlin/Views/BtwSession.swift

```swift
import Foundation

/// Manages a single /btw side-question exchange.
///
/// Sends one message directly to the provider using an isolated message array —
/// never touches the shared ContextManager or the conversation history.
@MainActor
final class BtwSession: ObservableObject {
    @Published private(set) var answer:    String?    = nil
    @Published private(set) var isLoading: Bool       = false
    @Published private(set) var error:     String?    = nil

    /// Sends `question` to `provider` and streams the response into `answer`.
    /// Completely isolated from the engine's ContextManager.
    func ask(question: String, provider: any LLMProviderProtocol) async {
        reset()
        isLoading = true
        defer { isLoading = false }

        // Build a minimal one-shot message list — just the user question.
        let messages: [Message] = [
            Message(role: .user, content: .text(question), timestamp: Date())
        ]

        do {
            var accumulated = ""
            // Use the provider's streaming API — match the pattern used in AgenticEngine
            // (typically `provider.stream(messages:tools:)` returning AsyncThrowingStream).
            for try await chunk in provider.stream(messages: messages, tools: []) {
                accumulated += chunk
                answer = accumulated
            }
        } catch {
            self.error = error.localizedDescription
            answer = nil
        }
    }

    /// Resets all fields to their initial state.
    func reset() {
        answer    = nil
        error     = nil
        isLoading = false
    }
}
```

Adapt `provider.stream(messages:tools:)` to whatever the actual `LLMProviderProtocol` streaming
method is named. Look at how `AgenticEngine` calls the provider — use the same call site pattern
but pass only `messages` (no tool definitions needed for btw queries).

---

## Write to: Merlin/Views/BtwOverlayView.swift

```swift
import SwiftUI

/// Floating overlay for /btw side questions.
///
/// Positioned as a sheet or popover over the chat area. Sends questions directly
/// to the active provider without touching the conversation history.
struct BtwOverlayView: View {
    @StateObject private var session = BtwSession()
    @State private var question: String
    @FocusState private var inputFocused: Bool
    var onDismiss: () -> Void
    var provider: any LLMProviderProtocol

    init(prefill: String = "", provider: any LLMProviderProtocol, onDismiss: @escaping () -> Void) {
        self._question  = State(initialValue: prefill)
        self.provider   = provider
        self.onDismiss  = onDismiss
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("Side question", systemImage: "bubble.left.and.bubble.right")
                    .font(.headline)
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss (Esc)")
            }

            Divider()

            // Input
            HStack(spacing: 8) {
                TextField("Ask anything…", text: $question, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .onSubmit { submit() }

                if session.isLoading {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Button { submit() } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            // Answer
            if let answer = session.answer {
                Divider()
                ScrollView {
                    Text(answer)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 300)
            } else if let error = session.error {
                Divider()
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .padding(16)
        .frame(width: 460)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 16, y: 4)
        .onAppear { inputFocused = true }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }

    private func submit() {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !session.isLoading else { return }
        Task { await session.ask(question: trimmed, provider: provider) }
    }
}
```

---

## Edit: Merlin/Views/ChatView.swift

### 1. Add state for overlay presentation

```swift
@State private var showBtwOverlay: Bool   = false
@State private var btwPrefill:     String = ""
```

### 2. Add `/btw` to `handleSlashCommandIfNeeded`

```swift
case "btw":
    // Extract everything after "/btw " as the prefill question.
    let prefill = message.dropFirst(4).trimmingCharacters(in: .whitespaces)
    btwPrefill     = String(prefill)
    showBtwOverlay = true
    return true
```

Handle the case where the command is just `/btw` (no argument) — sets `btwPrefill = ""`.

### 3. Present the overlay

Place this in the `body` (as a `.overlay` on the outer `VStack` or as a `.sheet`-style
popover anchored to the input bar). A `.overlay(alignment: .center)` approach works well
for a floating panel:

```swift
.overlay {
    if showBtwOverlay {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { showBtwOverlay = false }   // dismiss on outside click

        BtwOverlayView(
            prefill:   btwPrefill,
            provider:  appState.activeProvider,
            onDismiss: { showBtwOverlay = false }
        )
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }
}
.animation(.spring(duration: 0.18), value: showBtwOverlay)
```

`appState.activeProvider` should return the currently selected `LLMProviderProtocol`. Check
the `AppState` API — it may be `appState.registry.activeProvider` or similar. Use whichever
property gives the live provider instance.

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: BUILD SUCCEEDED. All BtwSessionTests pass. No regressions.

Manual verification:
1. Type `/btw What is 2+2?` → overlay opens pre-filled with "What is 2+2?", answer streams in.
2. Type `/btw` → overlay opens empty, cursor in input field.
3. Ask a question → answer appears; conversation history is unchanged.
4. Press Esc or click outside → overlay dismisses.
5. Agentic run continues unaffected while overlay was open.

## Commit

```bash
git add Merlin/Views/BtwSession.swift \
        Merlin/Views/BtwOverlayView.swift \
        Merlin/Views/ChatView.swift \
        TestHelpers/MockProvider.swift
git commit -m "Task 204b — /btw side-question overlay"
```
