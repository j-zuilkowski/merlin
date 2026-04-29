# Phase 104 — System Prompt Addendum (per-provider + domain)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 103b complete: PlannerEngine in place.

This phase wires `system_prompt_addendum` from provider config and the active domain
into `AgenticEngine.buildSystemPrompt()`. No new types — all wiring in existing files.

---

## ProviderConfig additions (add to Merlin/Providers/ProviderRegistry.swift or ProviderConfig model)

```swift
// Add to the ProviderConfig struct:
var systemPromptAddendum: String   // config.toml: [providers.X] system_prompt_addendum = "..."
```

config.toml schema:
```toml
[providers.mistral-7b]
system_prompt_addendum = "Always produce complete code blocks. Do not truncate."

[providers.deepseek-r1]
system_prompt_addendum = "Think through each step before writing code."
```

Load in ProviderRegistry or AppSettings where provider configs are parsed:
```swift
config.systemPromptAddendum = dict["system_prompt_addendum"] as? String ?? ""
```

---

## Edit: Merlin/Engine/AgenticEngine.swift — buildSystemPrompt()

```swift
// BEFORE:
private func buildSystemPrompt() -> String {
    var parts: [String] = []
    if !claudeMDContent.isEmpty {
        parts.append(claudeMDContent)
    }
    if !memoriesContent.isEmpty {
        parts.append(memoriesContent)
    }
    if permissionMode == .plan {
        parts.append(PermissionMode.planSystemPrompt)
    }
    parts.append("You are Merlin, a macOS agentic coding assistant. Use tools when helpful and keep responses concise.")
    return parts.joined(separator: "\n\n")
}

// AFTER:
private func buildSystemPrompt(for slot: AgentSlot = .execute) -> String {
    var parts: [String] = []
    if !claudeMDContent.isEmpty {
        parts.append(claudeMDContent)
    }
    if !memoriesContent.isEmpty {
        parts.append(memoriesContent)
    }
    if permissionMode == .plan {
        parts.append(PermissionMode.planSystemPrompt)
    }
    parts.append("You are Merlin, a macOS agentic coding assistant. Use tools when helpful and keep responses concise.")

    // Provider addendum — appended after base prompt, before domain addendum
    if let providerID = slotAssignments[slot],
       let config = registry?.providers.first(where: { $0.id == providerID }),
       !config.systemPromptAddendum.isEmpty {
        parts.append(config.systemPromptAddendum)
    }

    // Domain addendum — appended last
    if let domainAddendum = Task { await DomainRegistry.shared.activeDomain().systemPromptAddendum }
        .value, !domainAddendum.isEmpty {
        parts.append(domainAddendum)
    }

    return parts.joined(separator: "\n\n")
}
```

Also update `messagesWithSystem(_:)` to pass the current slot:
```swift
private func messagesForProvider(slot: AgentSlot = .execute) -> [Message] {
    return messagesWithSystem(contextManager.messagesForProvider(), slot: slot)
}

func messagesWithSystem(_ messages: [Message], slot: AgentSlot = .execute) -> [Message] {
    let systemPrompt = buildSystemPrompt(for: slot)
    guard !systemPrompt.isEmpty else { return messages }

    let systemMessage = Message(role: .system, content: .text(systemPrompt), timestamp: Date())
    if messages.first?.role == .system {
        var updated = messages
        updated[0] = systemMessage
        return updated
    } else {
        return [systemMessage] + messages
    }
}
```

And in `runLoop`, pass slot to `messagesForProvider`:
```swift
// BEFORE:
let request = CompletionRequest(
    model: requestModel,
    messages: messagesForProvider(),
    ...
)

// AFTER:
let request = CompletionRequest(
    model: requestModel,
    messages: messagesForProvider(slot: slot),
    ...
)
```

---

## Addendum hash utility (add to AgenticEngine or a shared location)

Used by `ModelPerformanceTracker` to track which addendum variant produced each outcome:

```swift
// In AgenticEngine — helper to produce addendum hash for the current slot:
func currentAddendumHash(for slot: AgentSlot) -> String {
    var addendum = ""
    if let providerID = slotAssignments[slot],
       let config = registry?.providers.first(where: { $0.id == providerID }) {
        addendum += config.systemPromptAddendum
    }
    // Domain addendum is always the same for a given domain activation, so include it
    return addendum.addendumHash
}
```

---

## Verify
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED; all existing tests still pass; zero warnings.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/AgenticEngine.swift \
        Merlin/Providers/ProviderRegistry.swift
git commit -m "Phase 104 — system_prompt_addendum injection (per-provider + domain, with addendum hash)"
```
