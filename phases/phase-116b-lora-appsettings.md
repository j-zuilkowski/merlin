# Phase 116b — LoRA AppSettings

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 116a complete: LoRASettingsTests (failing) in place.

---

## Edit: Merlin/Config/AppSettings.swift

### 1. Add seven published properties (after ragChunkLimit)

```swift
// BEFORE:
@Published var ragChunkLimit: Int = 3
@Published var xcalibreToken: String = ""

// AFTER:
@Published var ragChunkLimit: Int = 3

// MARK: - V6 LoRA self-training
// All off / empty by default. loraAutoTrain and loraAutoLoad are sub-toggles that
// only take effect when loraEnabled = true. Training runs via `mlx_lm.lora` on the
// local machine (M4 Mac); inference uses `mlx_lm.server` serving the fine-tuned adapter.
@Published var loraEnabled: Bool = false
@Published var loraAutoTrain: Bool = false
@Published var loraAutoLoad: Bool = false
@Published var loraMinSamples: Int = 50
@Published var loraBaseModel: String = ""
@Published var loraAdapterPath: String = ""
@Published var loraServerURL: String = ""

@Published var xcalibreToken: String = ""
```

### 2. Add fields to ConfigFile struct (after ragChunkLimit)

```swift
// After:  var ragChunkLimit: Int?
var loraEnabled: Bool?
var loraAutoTrain: Bool?
var loraAutoLoad: Bool?
var loraMinSamples: Int?
var loraBaseModel: String?
var loraAdapterPath: String?
var loraServerURL: String?
```

### 3. Add CodingKeys (after ragChunkLimit case)

```swift
// After:  case ragChunkLimit = "rag_chunk_limit"
case loraEnabled = "lora_enabled"
case loraAutoTrain = "lora_auto_train"
case loraAutoLoad = "lora_auto_load"
case loraMinSamples = "lora_min_samples"
case loraBaseModel = "lora_base_model"
case loraAdapterPath = "lora_adapter_path"
case loraServerURL = "lora_server_url"
```

### 4. Add serializedTOML() block (after ragChunkLimit block, before slotAssignments block)

```swift
// Add after the ragChunkLimit block:
if loraEnabled {
    lines.append("")
    lines.append("[lora]")
    lines.append("lora_enabled = true")
    if loraAutoTrain {
        lines.append("lora_auto_train = true")
    }
    if loraAutoLoad {
        lines.append("lora_auto_load = true")
    }
    if loraMinSamples != 50 {
        lines.append("lora_min_samples = \(loraMinSamples)")
    }
    if !loraBaseModel.isEmpty {
        lines.append("lora_base_model = \(quoted(loraBaseModel))")
    }
    if !loraAdapterPath.isEmpty {
        lines.append("lora_adapter_path = \(quoted(loraAdapterPath))")
    }
    if !loraServerURL.isEmpty {
        lines.append("lora_server_url = \(quoted(loraServerURL))")
    }
}
```

### 5. Add applyTOML() assignments (after ragChunkLimit assignments)

```swift
// Add after ragChunkLimit applyTOML lines:
if let v = config.loraEnabled       { loraEnabled = v }
if let v = config.loraAutoTrain     { loraAutoTrain = v }
if let v = config.loraAutoLoad      { loraAutoLoad = v }
if let v = config.loraMinSamples    { loraMinSamples = v }
if let v = config.loraBaseModel     { loraBaseModel = v }
if let v = config.loraAdapterPath   { loraAdapterPath = v }
if let v = config.loraServerURL     { loraServerURL = v }
```

---

## Verify
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'LoRASettings.*passed|LoRASettings.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -20
```
Expected: BUILD SUCCEEDED; LoRASettingsTests → 10 pass; all prior tests pass; zero warnings.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/Config/AppSettings.swift
git commit -m "Phase 116b — LoRA AppSettings (loraEnabled + 6 sub-settings, [lora] TOML section)"
```
