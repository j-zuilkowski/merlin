# Phase diag-12 — Engine Protocols

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete.
Working dir: ~/Documents/localProject/merlin

Four thin protocol files that allow `AgenticEngine`, tests, and calibration
flows to operate against mockable abstractions instead of concrete classes.
All live in `Merlin/Engine/Protocols/`.

---

## Files

### Merlin/Engine/Protocols/CriticEngineProtocol.swift

Abstracts the critic evaluation step. `CriticEngine` conforms via the
extension at the bottom. The 4-arg overload (with `writtenFiles`) has a
default implementation that forwards to the 3-arg version, so existing mocks
stay compatible without change.

```swift
import Foundation

protocol CriticEngineProtocol: Sendable {
    func evaluate(taskType: DomainTaskType, output: String, context: [Message]) async -> CriticResult
    /// Enhanced evaluation that cross-references written file contents.
    /// Default implementation forwards to the 3-param version (backward-compatible for mocks).
    func evaluate(taskType: DomainTaskType, output: String, context: [Message], writtenFiles: [String]) async -> CriticResult
}

extension CriticEngineProtocol {
    func evaluate(taskType: DomainTaskType, output: String, context: [Message], writtenFiles: [String]) async -> CriticResult {
        await evaluate(taskType: taskType, output: output, context: context)
    }
}

extension CriticEngine: CriticEngineProtocol {}
```

**Usage:** `AgenticEngine` holds `var critic: any CriticEngineProtocol`.
Tests inject a `MockCriticEngine` that returns canned `CriticResult` values.

---

### Merlin/Engine/Protocols/ModelPerformanceTrackerProtocol.swift

Abstracts outcome recording and profile queries. `ModelPerformanceTracker`
conforms via `@preconcurrency` extension (the concrete type is not Sendable
itself, so preconcurrency suppresses the warning). The 5-arg overload with
`prompt`/`response` has a default implementation dropping those fields,
preserving backward compatibility.

```swift
import Foundation

protocol ModelPerformanceTrackerProtocol: Sendable {
    func record(modelID: String, taskType: DomainTaskType, signals: OutcomeSignals) async
    func successRate(for modelID: String, taskType: DomainTaskType) -> Double?
    func profile(for modelID: String) -> [ModelPerformanceProfile]
    func allProfiles() -> [ModelPerformanceProfile]
    func records(for modelID: String, taskType: DomainTaskType) async -> [OutcomeRecord]
    func exportTrainingData(minScore: Double) async -> [OutcomeRecord]
}

extension ModelPerformanceTrackerProtocol {
    func record(
        modelID: String,
        taskType: DomainTaskType,
        signals: OutcomeSignals,
        prompt: String,
        response: String
    ) async {
        await record(
            modelID: modelID,
            taskType: taskType,
            signals: signals
        )
    }
}

extension ModelPerformanceTracker: @preconcurrency ModelPerformanceTrackerProtocol {}
```

---

### Merlin/Engine/Protocols/PlannerEngineProtocol.swift

Abstracts task classification and decomposition. `PlannerEngine` conforms
via extension. Two methods: `classify` returns a `ClassifierResult` (domain
tag + confidence); `decompose` returns an ordered list of `PlanStep` values.

```swift
import Foundation

protocol PlannerEngineProtocol: Sendable {
    func classify(message: String, domain: any DomainPlugin) async -> ClassifierResult
    func decompose(task: String, context: [Message]) async -> [PlanStep]
}

extension PlannerEngine: PlannerEngineProtocol {}
```

---

### Merlin/Engine/Protocols/XcalibreClientProtocol.swift

Abstracts the xcalibre-server RAG client. Enables offline tests by injecting
a `NullXcalibreClient` that returns empty arrays. `XcalibreClient` conforms
via extension.

```swift
import Foundation

protocol XcalibreClientProtocol: Sendable {
    func probe() async
    func isAvailable() async -> Bool
    func searchChunks(query: String, source: String, bookIDs: [String]?,
                      projectPath: String?, limit: Int, rerank: Bool) async -> [RAGChunk]
    func searchMemory(query: String, projectPath: String?, limit: Int) async -> [RAGChunk]
    func writeMemoryChunk(text: String, chunkType: String, sessionID: String?,
                          projectPath: String?, tags: [String]) async -> String?
    func deleteMemoryChunk(id: String) async
    func listBooks(limit: Int) async -> [RAGBook]
}

extension XcalibreClient: XcalibreClientProtocol {}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -10
```
Expected: BUILD SUCCEEDED (all four files already exist).

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/Protocols/CriticEngineProtocol.swift \
        Merlin/Engine/Protocols/ModelPerformanceTrackerProtocol.swift \
        Merlin/Engine/Protocols/PlannerEngineProtocol.swift \
        Merlin/Engine/Protocols/XcalibreClientProtocol.swift \
        tasks/task-diag-12-engine-protocols.md
git commit -m "Phase diag-12 — Engine protocol files (CriticEngineProtocol + ModelPerformanceTrackerProtocol + PlannerEngineProtocol + XcalibreClientProtocol)"
```
