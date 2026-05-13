# Phase 206b — LLM Summarisation Compaction

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 206a complete: failing LLMSummarisationCompactionTests.

See also: FEATURES.md § "Prompt Compression — LLM summarisation (recursive summarisation)"
Reference: https://machinelearningmastery.com/implementing-prompt-compression-to-reduce-agentic-loop-costs/

---

## Edit: Merlin/Engine/ContextManager.swift

### 1. Add `customDigest` parameter to `compact(force:)`

Change the private `compact(force: Bool)` signature to accept an optional custom summary string.
When `customDigest` is non-nil, use it verbatim as the text in the summary system message instead
of the auto-built preview snippet.

Find the summary construction inside `compact`:

```swift
let summary = Message(
    role: .system,
    content: .text(
        "[context compacted — \(groupsToRemove.count) tool exchange(s) summarised] \(digest)"
    ),
    timestamp: Date()
)
```

Replace with:

```swift
let summaryText = customDigest
    ?? "[context compacted — \(groupsToRemove.count) tool exchange(s) summarised] \(digest)"
let summary = Message(
    role: .system,
    content: .text(summaryText),
    timestamp: Date()
)
```

Update the method signature:

```swift
private func compact(force: Bool, customDigest: String? = nil) {
```

All existing callers (`append`, `forceCompaction`, `compactIfNeededBeforeRun`,
`compactIfNeededMidLoop`) omit `customDigest` and get `nil`, preserving existing behaviour.

### 2. Add `compactWithSummaryIfNeeded(provider:)` async method

After `compactIfNeededMidLoop()`, add:

```swift
/// Mid-loop async compaction with LLM summarisation.
///
/// When `estimatedTokens > midLoopCompactionThreshold`, collects the text of all removable
/// tool-exchange groups, calls `provider` for a one-shot narrative summary (no tools,
/// temperature 0), and compacts using that summary as the system-message digest.
/// Falls back to the static sentinel if the provider call throws.
/// Returns `true` when compaction fired, `false` when below threshold (no-op).
@discardableResult
func compactWithSummaryIfNeeded(provider: any LLMProvider) async -> Bool {
    guard estimatedTokens > midLoopCompactionThreshold else { return false }

    // Build exchange text from the same groups compact() would remove.
    let exchangeText = buildRemovableExchangeText()
    let digest: String?
    if let text = exchangeText, !text.isEmpty {
        digest = await summarise(text, using: provider)
    } else {
        digest = nil   // no removable groups → compact() will hard-truncate; digest unused
    }

    compact(force: true, customDigest: digest)
    return true
}

/// Extracts the text content of tool-exchange groups that `compact(force: true)` would remove.
/// Returns nil when there are no such groups (context is pure text turns).
private func buildRemovableExchangeText() -> String? {
    var groups: [(assistantIdx: Int, toolIndices: [Int])] = []
    var i = 0
    while i < messages.count {
        let msg = messages[i]
        guard msg.role == .assistant,
              let calls = msg.toolCalls, !calls.isEmpty else { i += 1; continue }
        var toolIndices: [Int] = []
        var j = i + 1
        while j < messages.count && messages[j].role == .tool {
            toolIndices.append(j)
            j += 1
        }
        if !toolIndices.isEmpty {
            groups.append((assistantIdx: i, toolIndices: toolIndices))
        }
        i = j
    }
    guard !groups.isEmpty else { return nil }

    let recentStart = max(0, messages.count - compactionKeepRecentTurns)
    let toRemove = groups.filter { $0.assistantIdx < recentStart }.isEmpty
        ? groups
        : groups.filter { $0.assistantIdx < recentStart }

    let lines: [String] = toRemove.flatMap { group -> [String] in
        var parts: [String] = []
        // Tool names from assistant message
        if let calls = messages[group.assistantIdx].toolCalls {
            let names = calls.map { $0.function.name }.joined(separator: ", ")
            parts.append("called: \(names)")
        }
        // First 200 chars of each tool result
        for idx in group.toolIndices {
            let content: String
            switch messages[idx].content {
            case .text(let t): content = String(t.prefix(200))
            case .parts: content = "(binary)"
            }
            parts.append("result: \(content)")
        }
        return parts
    }
    return lines.joined(separator: "\n")
}

/// Calls `provider` once to produce a short narrative summary of `exchangeText`.
/// Returns the provider's response text, or the raw `exchangeText` prefix as a fallback.
private func summarise(_ exchangeText: String, using provider: any LLMProvider) async -> String {
    let systemMsg = Message(
        role: .system,
        content: .text("Summarise the following tool-call exchanges in 2–3 concise sentences. Capture what tools were called and their key results. Be specific."),
        timestamp: Date()
    )
    let userMsg = Message(
        role: .user,
        content: .text(exchangeText),
        timestamp: Date()
    )
    var request = CompletionRequest(
        model: provider.resolvedModelID,
        messages: [systemMsg, userMsg]
    )
    request.tools = []
    request.maxTokens = 256

    do {
        let stream = try await provider.complete(request: request)
        var result = ""
        for try await chunk in stream {
            if let text = chunk.delta?.content { result += text }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(exchangeText.prefix(300))
            : result.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
        return String(exchangeText.prefix(300))
    }
}
```

---

## Edit: Merlin/Engine/AgenticEngine.swift

### 3. Replace `compactIfNeededMidLoop()` with the async LLM-summarisation call

In `runLoop()`, locate the two lines added in phase 205b:

```swift
// Prompt compression: compact if tool results have pushed tokens past the mid-loop threshold.
// Phase 206 will replace this with an async LLM-summarisation call.
context.compactIfNeededMidLoop()
emitCompactionNoteIfNeeded()
```

Replace them with:

```swift
// Prompt compression: mid-loop LLM summarisation (Phase 206b).
// Threshold check, exchange extraction, one-shot provider call, and compact happen inside.
_ = await context.compactWithSummaryIfNeeded(provider: provider)
emitCompactionNoteIfNeeded()
```

`provider` is the `any LLMProvider` local variable already in scope at this point in the loop
(resolved execute-slot provider for this iteration). No additional changes needed.

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: BUILD SUCCEEDED. All `LLMSummarisationCompactionTests` pass. No regressions in any compaction test suite.

Manual verification:
1. Run a long agentic session with many tool calls.
2. When the mid-loop compaction fires, the system note reads a natural-language summary of what the agent did (e.g. "read Engine.swift, located runLoop at line 550, patched lines 711–715, confirmed tests pass") instead of a raw token preview.
3. The agent continues normally and retains awareness of what it already completed.

## Commit

```bash
git add Merlin/Engine/ContextManager.swift \
        Merlin/Engine/AgenticEngine.swift
git commit -m "Phase 206b — LLM summarisation: mid-loop compaction replaces static sentinel with provider digest"
```
