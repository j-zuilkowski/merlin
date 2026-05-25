# Phase 117b — OutcomeRecord Training Fields

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 117a complete: OutcomeRecordTrainingFieldsTests (failing) in place.

---

## Edit: Merlin/Engine/ModelPerformanceTracker.swift

### 1. Add prompt and response fields to OutcomeRecord

```swift
// BEFORE:
struct OutcomeRecord: Codable, Sendable {
    var modelID: String
    var taskType: DomainTaskType
    var score: Double
    var addendumHash: String
    var timestamp: Date
}

// AFTER:
struct OutcomeRecord: Codable, Sendable {
    var modelID: String
    var taskType: DomainTaskType
    var score: Double
    var addendumHash: String
    var timestamp: Date
    /// The user message that triggered this session. Empty for records created before phase 117b.
    var prompt: String
    /// The model's final text response. Empty for records created before phase 117b.
    var response: String

    init(modelID: String, taskType: DomainTaskType, score: Double, addendumHash: String,
         timestamp: Date, prompt: String = "", response: String = "") {
        self.modelID = modelID
        self.taskType = taskType
        self.score = score
        self.addendumHash = addendumHash
        self.timestamp = timestamp
        self.prompt = prompt
        self.response = response
    }

    // Backward-compatible decode: old JSON missing prompt/response decodes as ""
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        modelID       = try c.decode(String.self, forKey: .modelID)
        taskType      = try c.decode(DomainTaskType.self, forKey: .taskType)
        score         = try c.decode(Double.self, forKey: .score)
        addendumHash  = try c.decode(String.self, forKey: .addendumHash)
        timestamp     = try c.decode(Date.self, forKey: .timestamp)
        prompt        = (try? c.decode(String.self, forKey: .prompt)) ?? ""
        response      = (try? c.decode(String.self, forKey: .response)) ?? ""
    }
}
```

### 2. Update record() to accept prompt and response

```swift
// BEFORE:
func record(modelID: String, taskType: DomainTaskType, signals: OutcomeSignals) async {
    let key = profileKey(modelID: modelID, taskType: taskType, addendumHash: signals.addendumHash)
    let score = computeScore(from: signals)
    let record = OutcomeRecord(
        modelID: modelID,
        taskType: taskType,
        score: score,
        addendumHash: signals.addendumHash,
        timestamp: Date()
    )
    ...
}

// AFTER:
func record(modelID: String, taskType: DomainTaskType, signals: OutcomeSignals,
            prompt: String = "", response: String = "") async {
    let key = profileKey(modelID: modelID, taskType: taskType, addendumHash: signals.addendumHash)
    let score = computeScore(from: signals)
    let record = OutcomeRecord(
        modelID: modelID,
        taskType: taskType,
        score: score,
        addendumHash: signals.addendumHash,
        timestamp: Date(),
        prompt: prompt,
        response: response
    )
    ...
}
```

### 3. Update exportTrainingData to exclude empty-text records

```swift
// BEFORE:
func exportTrainingData(minScore: Double) async -> [OutcomeRecord] {
    records.values
        .flatMap { $0 }
        .filter { $0.score >= minScore }
        .sorted { $0.timestamp < $1.timestamp }
}

// AFTER:
func exportTrainingData(minScore: Double) async -> [OutcomeRecord] {
    records.values
        .flatMap { $0 }
        .filter { $0.score >= minScore && !$0.prompt.isEmpty && !$0.response.isEmpty }
        .sorted { $0.timestamp < $1.timestamp }
}
```

---

## Edit: Merlin/Engine/Protocols/ModelPerformanceTrackerProtocol.swift

### Add the extended record signature; provide backward-compat default via extension

```swift
// BEFORE:
protocol ModelPerformanceTrackerProtocol: Sendable {
    func record(modelID: String, taskType: DomainTaskType, signals: OutcomeSignals) async
    ...
}

// AFTER:
protocol ModelPerformanceTrackerProtocol: Sendable {
    func record(modelID: String, taskType: DomainTaskType, signals: OutcomeSignals,
                prompt: String, response: String) async
    func successRate(for modelID: String, taskType: DomainTaskType) -> Double?
    func profile(for modelID: String) -> [ModelPerformanceProfile]
    func allProfiles() -> [ModelPerformanceProfile]
    func records(for modelID: String, taskType: DomainTaskType) async -> [OutcomeRecord]
    func exportTrainingData(minScore: Double) async -> [OutcomeRecord]
}

/// Backward-compatible 3-argument form. Existing callers compile unchanged.
extension ModelPerformanceTrackerProtocol {
    func record(modelID: String, taskType: DomainTaskType, signals: OutcomeSignals) async {
        await record(modelID: modelID, taskType: taskType, signals: signals,
                     prompt: "", response: "")
    }
}
```

---

## Edit: Merlin/Engine/AgenticEngine.swift — track lastResponseText and pass to record()

### 1. Declare lastResponseText before the while loop

```swift
// BEFORE (line ~356):
lastCriticVerdict = nil
var loopCount = 0

// AFTER:
lastCriticVerdict = nil
var lastResponseText = ""
var loopCount = 0
```

### 2. Capture fullText when the loop exits cleanly (no tool calls)

```swift
// In the guard sawToolCall, !assembled.isEmpty else { ... } block,
// just before the critic evaluation:
// AFTER the "guard sawToolCall" line, at the top of the else block:
lastResponseText = fullText
```

### 3. Pass prompt and response to performanceTracker.record()

```swift
// BEFORE:
await performanceTracker.record(
    modelID: slotAssignments[workingSlot] ?? "",
    taskType: taskType,
    signals: signals
)

// AFTER:
await performanceTracker.record(
    modelID: slotAssignments[workingSlot] ?? "",
    taskType: taskType,
    signals: signals,
    prompt: userMessage,
    response: lastResponseText
)
```

---

## Verify
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'OutcomeRecord.*passed|OutcomeRecord.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -20
```
Expected: BUILD SUCCEEDED; OutcomeRecordTrainingFieldsTests → 6 pass; all prior tests pass; zero warnings.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/ModelPerformanceTracker.swift \
        Merlin/Engine/Protocols/ModelPerformanceTrackerProtocol.swift \
        Merlin/Engine/AgenticEngine.swift
git commit -m "Phase 117b — OutcomeRecord prompt/response fields; record() captures conversation text"
```
