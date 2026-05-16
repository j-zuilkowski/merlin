# Phase 295b — Subagent Block HTML (implementation)

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Phase 295a complete: failing tests in `SubagentBlockHTMLTests`. Unit B2 of the plan.

The renderer is a pure `static` function over `[ChatEntry]` — it cannot read the
`subagentVMs` dictionary. So the render-relevant subagent state is mirrored onto the
`ChatEntry` as a value snapshot; `SubagentBlockViewModel` stays as the live accumulator.

## Write to: Merlin/Views/Chat/SubagentBlock.swift (new)

```swift
import Foundation

/// One tool invocation inside a subagent block.
struct SubagentToolLine: Sendable, Equatable {
    let name: String
    let done: Bool
}

/// A value snapshot of a subagent's state, carried on a `ChatEntry` so the pure
/// `ConversationHTMLRenderer` can render it without reading a view model.
struct SubagentBlock: Sendable, Equatable {
    var agentName: String
    var status: String          // "running" | "completed" | "failed"
    var tools: [SubagentToolLine]
    var summary: String?
    var text: String
}
```

## Edit: Merlin/Views/ChatView.swift

### 1. `ChatEntry` — add the field
Add `var subagentBlock: SubagentBlock? = nil` to `struct ChatEntry`.

### 2. `ChatViewModel.applyEngineEvent` — populate it
- `.subagentStarted(id, agentName)`: when creating the `ChatEntry` (it already sets
  `subagentID`), also set
  `entry.subagentBlock = SubagentBlock(agentName: agentName, status: "running",
  tools: [], summary: nil, text: "")`.
- `.subagentUpdate(id, event)`: after `subagentVMs[id]?.apply(event)`, derive a fresh
  snapshot from the view model and assign it to the matching entry, then `bumpRevision()`:

```swift
if let vm = subagentVMs[id],
   let idx = items.firstIndex(where: { $0.subagentID == id }) {
    let statusString: String
    switch vm.status {
    case .running:   statusString = "running"
    case .completed: statusString = "completed"
    case .failed:    statusString = "failed"
    }
    items[idx].subagentBlock = SubagentBlock(
        agentName: vm.agentName,
        status: statusString,
        tools: vm.toolEvents.map {
            SubagentToolLine(name: $0.toolName, done: $0.status == .done)
        },
        summary: vm.summary,
        text: vm.accumulatedText)
}
```

## Edit: Merlin/Views/Chat/ConversationHTMLRenderer.swift
In `assistantHTML(_:)`, when `entry.subagentBlock` is non-nil, render a `subagent-block`
`<details>` and include it in the bubble (before `textDiv` is fine — subagent entries
have empty `text`). Add a `subagentBlockHTML(_ block: SubagentBlock) -> String` helper:
header shows `[agentName]` and a status dot/word; body lists each tool line (name +
done/running) and the accumulated `text` / `summary`. Escape every string via
`htmlEscape`. Add matching CSS in `htmlDocument` styled like `.tool-row`.

## Delete: Merlin/UI/Chat/SubagentBlockView.swift
Superseded by HTML rendering (this file also contains `SubagentToolEventRowView`; remove
the whole file). `SubagentBlockViewModel` stays — it remains the event accumulator.
Run `xcodegen generate` after deletion.

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/SubagentBlockHTMLTests \
  -only-testing:MerlinTests/SubagentBlockViewModelTests
```
Expected: BUILD SUCCEEDED, all tests pass.

Runtime check: build + launch, run a turn that spawns a subagent, confirm an inline
`[agent] …` block appears in the chat and updates as the subagent runs.

## Commit
```
git add Merlin/Views/Chat/SubagentBlock.swift Merlin/Views/ChatView.swift \
  Merlin/Views/Chat/ConversationHTMLRenderer.swift phases/phase-295b-subagent-block-html.md
git rm Merlin/UI/Chat/SubagentBlockView.swift
git commit -m "Phase 295b — Subagent block HTML"
```
