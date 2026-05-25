# Phase 51 — Reasoning Effort + Personalization + Context Usage Indicator

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 50b complete: WebSearchTool in place.

This phase adds three tightly coupled UX features controlled by AppSettings:
1. **Reasoning effort selector** — per-model; hidden when unsupported
2. **Personalization** — standing instructions already in AppSettings; UI wiring + injection
3. **Context usage indicator** — token counter badge + `/status` command response

No separate a/b split — all three are small enough to deliver together.
Tests live in `MerlinTests/Unit/ReasoningEffortTests.swift`.

---

## Tests: MerlinTests/Unit/ReasoningEffortTests.swift

```swift
import XCTest
@testable import Merlin

final class ReasoningEffortTests: XCTestCase {

    // MARK: - ProviderRegistry.reasoningEffortSupported

    func test_anthropicClaude3Opus_supported() {
        XCTAssertTrue(ProviderRegistry.reasoningEffortSupported(for: "claude-3-opus-20240229"))
    }

    func test_claude3Haiku_notSupported() {
        XCTAssertFalse(ProviderRegistry.reasoningEffortSupported(for: "claude-3-haiku-20240307"))
    }

    func test_lmStudio_qwq_supported() {
        XCTAssertTrue(ProviderRegistry.reasoningEffortSupported(for: "qwq-32b-preview"))
    }

    func test_lmStudio_deepseekR1_supported() {
        XCTAssertTrue(ProviderRegistry.reasoningEffortSupported(for: "deepseek-r1-distill-qwen-7b"))
    }

    func test_lmStudio_r1Prefix_supported() {
        XCTAssertTrue(ProviderRegistry.reasoningEffortSupported(for: "r1-lite-preview"))
    }

    func test_lmStudio_llama_notSupported() {
        XCTAssertFalse(ProviderRegistry.reasoningEffortSupported(for: "llama-3.2-3b"))
    }

    func test_override_enablesUnsupportedModel() {
        let overrides = ["llama-3.2-3b": true]
        XCTAssertTrue(ProviderRegistry.reasoningEffortSupported(for: "llama-3.2-3b", overrides: overrides))
    }

    func test_override_disablesSupportedModel() {
        let overrides = ["qwq-32b-preview": false]
        XCTAssertFalse(ProviderRegistry.reasoningEffortSupported(for: "qwq-32b-preview", overrides: overrides))
    }

    func test_unknownModel_notSupported() {
        XCTAssertFalse(ProviderRegistry.reasoningEffortSupported(for: "some-unknown-model-v1"))
    }

    // MARK: - ReasoningEffort enum

    func test_reasoningEffort_allCases() {
        XCTAssertEqual(ReasoningEffort.allCases.count, 3)
    }

    func test_reasoningEffort_apiValues() {
        XCTAssertEqual(ReasoningEffort.high.apiValue, "high")
        XCTAssertEqual(ReasoningEffort.medium.apiValue, "medium")
        XCTAssertEqual(ReasoningEffort.low.apiValue, "low")
    }

    // MARK: - ContextUsageTracker

    func test_contextUsage_initialZero() {
        let tracker = ContextUsageTracker(contextWindowSize: 200_000)
        XCTAssertEqual(tracker.usedTokens, 0)
        XCTAssertEqual(tracker.percentUsed, 0.0, accuracy: 0.001)
    }

    func test_contextUsage_update() {
        let tracker = ContextUsageTracker(contextWindowSize: 100_000)
        tracker.update(usedTokens: 50_000)
        XCTAssertEqual(tracker.usedTokens, 50_000)
        XCTAssertEqual(tracker.percentUsed, 0.5, accuracy: 0.001)
    }

    func test_contextUsage_statusString() {
        let tracker = ContextUsageTracker(contextWindowSize: 200_000)
        tracker.update(usedTokens: 40_000)
        let status = tracker.statusString
        XCTAssertTrue(status.contains("40,000") || status.contains("40000"))
        XCTAssertTrue(status.contains("20%") || status.contains("20.0%"))
    }
}
```

---

## New files

### Merlin/Providers/ReasoningEffort.swift

```swift
import Foundation

enum ReasoningEffort: String, CaseIterable, Codable, Sendable {
    case high, medium, low

    var apiValue: String { rawValue }

    var label: String {
        switch self {
        case .high:   return "High"
        case .medium: return "Medium"
        case .low:    return "Low"
        }
    }
}
```

### Merlin/Providers/ProviderRegistry+ReasoningEffort.swift

```swift
import Foundation

extension ProviderRegistry {

    // Known model IDs that support reasoning effort (Anthropic extended thinking models).
    private static let knownReasoningModels: Set<String> = [
        "claude-3-opus-20240229",
        "claude-3-7-sonnet-20250219",
        "claude-opus-4",
        "claude-sonnet-4",
    ]

    // LM Studio models detected by name pattern.
    private static let reasoningPatterns: [String] = [
        "qwq", "deepseek-r1", "r1-"
    ]

    /// Returns true if the given model ID supports reasoning effort selection.
    /// `overrides` comes from `AppSettings.reasoningEnabledOverrides` (written to config.toml).
    static func reasoningEffortSupported(
        for modelID: String,
        overrides: [String: Bool] = [:]
    ) -> Bool {
        // User override takes priority
        if let override = overrides[modelID] { return override }
        // Static known list
        if knownReasoningModels.contains(modelID) { return true }
        // Pattern matching for LM Studio models
        let lower = modelID.lowercased()
        return reasoningPatterns.contains { lower.contains($0) }
    }
}
```

### Merlin/Engine/ContextUsageTracker.swift

```swift
import Foundation

// Tracks context window consumption. Updated after each API response.
@MainActor
final class ContextUsageTracker: ObservableObject {

    let contextWindowSize: Int
    @Published private(set) var usedTokens: Int = 0

    init(contextWindowSize: Int) {
        self.contextWindowSize = contextWindowSize
    }

    func update(usedTokens: Int) {
        self.usedTokens = usedTokens
    }

    var percentUsed: Double {
        guard contextWindowSize > 0 else { return 0 }
        return Double(usedTokens) / Double(contextWindowSize)
    }

    var statusString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let usedStr = formatter.string(from: NSNumber(value: usedTokens)) ?? "\(usedTokens)"
        let pct = Int(percentUsed * 100)
        return "Context: \(usedStr) / \(formatter.string(from: NSNumber(value: contextWindowSize)) ?? "\(contextWindowSize)") tokens (\(pct)%)"
    }
}
```

---

## UI changes

### Reasoning effort selector (ChatInputView or toolbar)

Add a `Picker` for `ReasoningEffort` that is hidden when the current model doesn't support it:

```swift
// In ChatInputView or session toolbar:
if ProviderRegistry.reasoningEffortSupported(
    for: settings.modelID,
    overrides: settings.reasoningEnabledOverrides
) {
    Picker("Effort", selection: $sessionReasoningEffort) {
        ForEach(ReasoningEffort.allCases, id: \.self) { level in
            Text(level.label).tag(level)
        }
    }
    .pickerStyle(.segmented)
    .frame(width: 200)
}
```

### Standing instructions injection

In `AgenticEngine` system prompt construction, append standing instructions from AppSettings:

```swift
var systemPrompt = baseSystemPrompt
let standing = AppSettings.shared.standingInstructions
if !standing.isEmpty {
    systemPrompt += "\n\n---\n\(standing)"
}
```

### Context usage badge

Show `contextTracker.statusString` in the session toolbar or footer as a secondary label.
Update `contextTracker.update(usedTokens:)` from the `usage` field in each API response.

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED, all ReasoningEffortTests pass.

## Commit
```bash
git add MerlinTests/Unit/ReasoningEffortTests.swift \
        Merlin/Providers/ReasoningEffort.swift \
        Merlin/Providers/ProviderRegistry+ReasoningEffort.swift \
        Merlin/Engine/ContextUsageTracker.swift
git commit -m "Phase 51 — Reasoning effort selector, personalization injection, context usage tracker"
```
