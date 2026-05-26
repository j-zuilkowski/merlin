# Task 165b — DPO Pair Collection Implementation

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 165a complete: failing tests in DPOQueueTests.swift + DPOAutoFilterTests.swift.

---

## Changes

### 1. New file: Merlin/Engine/DPOQueue.swift

```swift
import Foundation

// MARK: - DPOPendingEntry

/// A single DPO (Direct Preference Optimization) training pair awaiting user review.
/// Stored as JSON at `~/.merlin/lora/pending/<uuid>.json`.
///
/// - `prompt`   — the user message that triggered the model response
/// - `chosen`   — the preferred (user-corrected) response
/// - `rejected` — the original model response that was corrected
/// - `modelID`  — provider model identifier at time of generation
/// - `timestamp` — when the pair was captured
struct DPOPendingEntry: Codable, Sendable, Identifiable {
    var id: String
    var prompt: String
    var chosen: String
    var rejected: String
    var modelID: String
    var timestamp: Date

    init(
        id: String = UUID().uuidString,
        prompt: String,
        chosen: String,
        rejected: String,
        modelID: String,
        timestamp: Date
    ) {
        self.id = id
        self.prompt = prompt
        self.chosen = chosen
        self.rejected = rejected
        self.modelID = modelID
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case id
        case prompt
        case chosen
        case rejected
        case modelID = "model_id"
        case timestamp
    }
}

// MARK: - DPOQueue

/// Manages the `~/.merlin/lora/pending/` queue of proposed DPO training pairs.
///
/// Each entry is stored as a separate JSON file named `<uuid>.json`.
/// This mirrors the memories `pending/` pattern — items wait for user approval
/// before entering the training corpus.
actor DPOQueue {

    private let pendingDirectory: URL

    /// Default init using `~/.merlin/lora/pending/`
    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.pendingDirectory = home
            .appendingPathComponent(".merlin")
            .appendingPathComponent("lora")
            .appendingPathComponent("pending")
    }

    /// Test init accepting an arbitrary directory.
    init(pendingDirectory: URL) {
        self.pendingDirectory = pendingDirectory
    }

    // MARK: - Write

    /// Persist `entry` as `<entry.id>.json` in the pending directory.
    /// Creates the directory if it does not exist.
    func propose(entry: DPOPendingEntry) throws {
        // Ensure directory exists
        if !FileManager.default.fileExists(atPath: pendingDirectory.path) {
            try FileManager.default.createDirectory(
                at: pendingDirectory,
                withIntermediateDirectories: true
            )
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(entry)
        let fileURL = pendingDirectory.appendingPathComponent("\(entry.id).json")
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Read

    /// Load and return all valid pending entries from the directory.
    /// Silently skips files that cannot be decoded.
    func pendingEntries() -> [DPOPendingEntry] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: pendingDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> DPOPendingEntry? in
                guard let data = try? Data(contentsOf: url),
                      let entry = try? decoder.decode(DPOPendingEntry.self, from: data)
                else { return nil }
                return entry
            }
            .sorted { $0.timestamp < $1.timestamp }
    }
}
```

---

### 2. AppSettings.swift — add dpoEnabled

Add after `maxCriticRetries`:

```swift
    /// TOML key `dpo_enabled`. Default: `true`. Set to false to disable DPO pair collection.
    @Published var dpoEnabled: Bool = true
```

In `ConfigFile`, add to the `CriticConfig` struct (or create a separate `DPOConfig` — using CriticConfig is fine since it's the same subsystem):

Option A — add to existing `CriticConfig`:
```swift
        struct CriticConfig: Codable, Sendable {
            var criticEnabled: Bool?
            var maxCriticRetries: Int?
            var dpoEnabled: Bool?

            enum CodingKeys: String, CodingKey {
                case criticEnabled = "critic_enabled"
                case maxCriticRetries = "max_critic_retries"
                case dpoEnabled = "dpo_enabled"
            }
        }
```

In `apply(to settings:)`:
```swift
        if let v = critic?.dpoEnabled { settings.dpoEnabled = v }
```

---

### 3. AgenticEngine.swift — add dpoQueue + propose at turn end

**Step A — Add dpoQueue property**

Near the other test-injection vars (around line 79, after `criticOverride`):

```swift
    /// DPO queue for proposing training pairs. Injected in tests; defaults to the
    /// shared `~/.merlin/lora/pending/` queue in production.
    var dpoQueue: DPOQueue = DPOQueue()
```

**Step B — Correction keyword detection**

Add a private helper near the bottom of AgenticEngine (before or after `makeCritic`):

```swift
    /// Returns true when `message` starts with a phrase that signals the user
    /// is correcting a previous response. Heuristic — false positives are harmless
    /// (DPO items go into a pending queue awaiting user review anyway).
    private func isCorrectionMessage(_ message: String) -> Bool {
        let lower = message.lowercased()
        let keywords = [
            "that's wrong", "thats wrong",
            "that is wrong", "that is incorrect",
            "that's incorrect", "thats incorrect",
            "no, ", "no that", "not quite",
            "actually,", "actually that",
            "you're wrong", "youre wrong",
            "wrong,", "wrong.", "incorrect,", "incorrect.",
            "please fix", "fix this", "fix the",
            "that doesn't", "that doesnt",
            "that isn't", "that isnt",
            "that won't", "that wont",
        ]
        return keywords.contains { lower.hasPrefix($0) || lower.contains(": \($0)") }
    }
```

**Step C — Store last-turn data for DPO pairing**

Add instance vars for DPO context capture (near the other mutable state vars, around line 75):

```swift
    /// Stores the user prompt from the most recent completed turn (for DPO pairing).
    private var lastUserPrompt: String = ""
    /// Stores the model response from the most recent completed turn (for DPO pairing).
    private var lastModelResponse: String = ""
    /// Stores the model ID used in the most recent completed turn (for DPO pairing).
    private var lastModelID: String = ""
```

**Step D — Capture values at end of turn**

In `runLoop`, just before the `performanceTracker.record(...)` call (~line 939), add:

```swift
        // Capture for potential DPO pairing on the next turn
        lastUserPrompt = userMessage
        lastModelResponse = lastResponseText
        lastModelID = trackerModelID
```

**Step E — Propose DPO pair when correction detected**

At the top of `runLoop` (or `send`), after capturing `userMessage`, add the DPO proposal
for the *previous* turn if the *current* message looks like a correction.

In the `send(userMessage:)` method (or at the start of `runLoop`), add before any other logic:

```swift
        // Check if this turn is a correction of the previous — if so, propose a DPO pair.
        // The "chosen" side is left empty for now (user provides it via the review queue UI).
        // The "rejected" side is the original model response that's being corrected.
        let dpoIsEnabled = await MainActor.run { AppSettings.shared.dpoEnabled }
        if dpoIsEnabled,
           !lastModelResponse.isEmpty,
           isCorrectionMessage(userMessage) {
            let entry = DPOPendingEntry(
                prompt: lastUserPrompt,
                chosen: "",          // user fills this in via the pending review queue
                rejected: lastModelResponse,
                modelID: lastModelID,
                timestamp: Date()
            )
            try? await dpoQueue.propose(entry: entry)
        }
```

> **Note on `chosen` being empty:** The architecture specifies that DPO pairs go into a
> pending review queue where the user can Accept + Edit (filling in the chosen response)
> or Decline. Leaving `chosen` empty at proposal time matches the queue UX — the user
> supplies the preferred version during review. A non-empty `chosen` will be added in a
> future task that wires the review queue UI.

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED, all DPOQueueTests and DPOAutoFilterTests pass.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/DPOQueue.swift \
        Merlin/Config/AppSettings.swift \
        Merlin/Engine/AgenticEngine.swift
git commit -m "Task 165b — DPOQueue + correction-triggered DPO pair collection"
```
