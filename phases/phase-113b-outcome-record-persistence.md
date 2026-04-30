# Phase 113b — OutcomeRecord Persistence

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 113a complete: OutcomeRecordPersistenceTests (failing) in place.

Note: ModelPerformanceProfile is already persisted. This phase adds persistence for the raw
OutcomeRecord array — the V6 LoRA training dataset source.

---

## Edit: Merlin/Engine/ModelPerformanceTracker.swift

### 1. Persist records in record()

```swift
// In record(modelID:taskType:signals:), after updating the in-memory records dict:
// BEFORE:
records[key, default: []].append(record)
updateProfile(...)
saveToDisk(modelID: modelID)

// AFTER:
records[key, default: []].append(record)
updateProfile(...)
saveToDisk(modelID: modelID)
saveRecordsToDisk(modelID: modelID)    // ← add this line
```

### 2. Load records at init

```swift
// In init(storageURL:), after loading profiles:
// BEFORE:
profiles = Self.loadProfiles(from: storageURL)

// AFTER:
profiles = Self.loadProfiles(from: storageURL)
records = Self.loadRecords(from: storageURL)   // ← add this line
```

### 3. Add records(for:taskType:) public method

```swift
/// Returns all persisted OutcomeRecords for a given model + task type.
/// Used by V6 LoRA training to build the fine-tuning dataset.
func records(for modelID: String, taskType: DomainTaskType) async -> [OutcomeRecord] {
    records.values
        .flatMap { $0 }
        .filter { $0.modelID == modelID && $0.taskType == taskType }
        .sorted { $0.timestamp < $1.timestamp }
}
```

### 4. Add exportTrainingData(minScore:) public method

```swift
/// Returns all OutcomeRecords with score >= minScore across all models and task types.
/// The caller formats these as instruction/response pairs for LoRA fine-tuning.
/// minScore: 0.0–1.0; recommended minimum 0.7 to exclude poor-quality examples.
func exportTrainingData(minScore: Double) async -> [OutcomeRecord] {
    records.values
        .flatMap { $0 }
        .filter { $0.score >= minScore }
        .sorted { $0.timestamp < $1.timestamp }
}
```

### 5. Add saveRecordsToDisk(modelID:) private method

```swift
private func saveRecordsToDisk(modelID: String) {
    let modelRecords = records.values
        .flatMap { $0 }
        .filter { $0.modelID == modelID }

    guard !modelRecords.isEmpty else { return }

    let sanitised = modelID.replacingOccurrences(of: "/", with: "_")
    let fileURL = storageURL.appendingPathComponent("records-\(sanitised).json")

    try? FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
    if let data = try? JSONEncoder().encode(modelRecords) {
        try? data.write(to: fileURL, options: .atomic)
    }
}
```

### 6. Add loadRecords(from:) private static method

```swift
private static func loadRecords(from storageURL: URL) -> [String: [OutcomeRecord]] {
    guard let files = try? FileManager.default.contentsOfDirectory(
        at: storageURL, includingPropertiesForKeys: nil
    ) else { return [:] }

    var loaded: [String: [OutcomeRecord]] = [:]

    for file in files where file.lastPathComponent.hasPrefix("records-") &&
                             file.pathExtension == "json" {
        guard let data = try? Data(contentsOf: file),
              let fileRecords = try? JSONDecoder().decode([OutcomeRecord].self, from: data)
        else { continue }

        for record in fileRecords {
            let key = "\(record.modelID)|\(record.taskType.domainID)|\(record.taskType.name)|\(record.addendumHash)"
            loaded[key, default: []].append(record)
        }
    }

    // Deduplicate by timestamp (in case of duplicate writes)
    return loaded.mapValues { records in
        Array(Dictionary(grouping: records, by: \.timestamp.timeIntervalSince1970)
            .values.compactMap(\.first))
        .sorted { $0.timestamp < $1.timestamp }
    }
}
```

### 7. Also update ModelPerformanceTrackerProtocol

```swift
// Add to Merlin/Engine/Protocols/ModelPerformanceTrackerProtocol.swift:
func records(for modelID: String, taskType: DomainTaskType) async -> [OutcomeRecord]
func exportTrainingData(minScore: Double) async -> [OutcomeRecord]
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
Expected: BUILD SUCCEEDED; OutcomeRecordPersistenceTests → 6 pass; all prior tests pass; zero warnings.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/ModelPerformanceTracker.swift \
        Merlin/Engine/Protocols/ModelPerformanceTrackerProtocol.swift
git commit -m "Phase 113b — OutcomeRecord persistence (V6 training data survives restarts)"
```
