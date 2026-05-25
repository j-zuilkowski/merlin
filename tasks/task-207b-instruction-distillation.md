# Task 207b — Instruction Distillation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 207a complete: failing InstructionDistillationTests.

See also: FEATURES.md § "Prompt Compression — Instruction distillation"
Reference: https://machinelearningmastery.com/implementing-prompt-compression-to-reduce-agentic-loop-costs/

---

## Edit: Merlin/Config/AppSettings.swift

### 1. Add `promptCompressionEnabled` published property

After the existing `@Published var dpoEnabled: Bool = true` line, add:

```swift
@Published var promptCompressionEnabled: Bool = false
```

### 2. Add `promptCompressionEnabled` to `ConfigFile`

In `ConfigFile`, after `var dpoEnabled: Bool?`, add:

```swift
var promptCompressionEnabled: Bool?
```

### 3. Add CodingKey mapping

In `ConfigFile.CodingKeys`, after `case dpoEnabled = "dpo_enabled"`, add:

```swift
case promptCompressionEnabled = "prompt_compression_enabled"
```

### 4. Apply from loaded config

In the `apply(_ config: ConfigFile)` method (or wherever `dpoEnabled` is applied), add:

```swift
if let value = config.promptCompressionEnabled {
    promptCompressionEnabled = value
}
```

### 5. Serialise to TOML

In `serializedTOML()` (or `buildTOML()`), in the main settings section alongside `dpo_enabled`, add:

```swift
if promptCompressionEnabled {
    lines.append("prompt_compression_enabled = true")
}
```

---

## Edit: Merlin/Engine/AgenticEngine.swift

### 6. Add distillation state properties

After the existing `var constitutionContent: String = ""` property, add:

```swift
/// SHA256 hex of the `constitutionContent` that was most recently distilled.
/// Empty string when no distillation has been performed yet.
var constitutionDistillHash: String = ""

/// Compressed equivalent of `constitutionContent` produced by `refreshDistilledConstitution(using:)`.
/// Empty string until the first distillation completes.
var constitutionDistilledContent: String = ""
```

### 7. Add `distilledCoreSystemPrompt` static property

After `private static var coreSystemPrompt: String { … }`, add:

```swift
/// Token-efficient distilled version of `coreSystemPrompt`.
/// Encodes the same constraints in ~6 compact lines (~80 tokens) vs 18 prose lines (~350 tokens).
/// Used by `buildStablePrefix()` when `AppSettings.shared.promptCompressionEnabled` is true.
static var distilledCoreSystemPrompt: String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    let today = formatter.string(from: Date())
    return """
    Merlin=macOS agentic coder. Date:\(today).
    FILE: search_files/run_shell(grep/rg/find)→locate→read_file(targeted). list_directory(recursive)→structure.
    PREFER: tools>prose. Responses concise. Avoid sequential bulk reads.
    """
}

/// Exposed for test comparison against `distilledCoreSystemPrompt`. Identical to `coreSystemPrompt`.
static var coreSystemPromptForTesting: String { coreSystemPrompt }
```

### 8. Add `refreshDistilledConstitution(using:)` async method

After `buildStablePrefix()`, add:

```swift
/// Distils `constitutionContent` using `provider` when the content has changed since the last
/// distillation. Uses a SHA256 hash of the content as a cache key — the provider is called
/// at most once per unique `constitutionContent` value. No-op when content is empty or unchanged.
func refreshDistilledConstitution(using provider: any LLMProvider) async {
    guard !constitutionContent.isEmpty else { return }
    let currentHash = sha256Hex(constitutionContent)
    guard currentHash != constitutionDistillHash else { return }

    let systemMsg = Message(
        role: .system,
        content: .text(
            "Compress the following constitution.md into a token-efficient shorthand that preserves all " +
            "constraints, rules, and technical details. Use abbreviations, symbols, and dense phrasing. " +
            "Output only the compressed text — no preamble."
        ),
        timestamp: Date()
    )
    let userMsg = Message(role: .user, content: .text(constitutionContent), timestamp: Date())
    var request = CompletionRequest(model: provider.resolvedModelID, messages: [systemMsg, userMsg])
    request.tools = []
    request.maxTokens = 1_024

    do {
        let stream = try await provider.complete(request: request)
        var result = ""
        for try await chunk in stream {
            if let text = chunk.delta?.content { result += text }
        }
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            constitutionDistilledContent = trimmed
            constitutionDistillHash = currentHash
        }
    } catch {
        // Distillation failed — keep previous distilled content (or empty); do not update hash.
        // buildStablePrefix() will fall back to the original constitutionContent.
    }
}

/// Returns the lowercase hex SHA256 digest of `string`.
private func sha256Hex(_ string: String) -> String {
    let data = Data(string.utf8)
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}
```

Add `import CryptoKit` at the top of `AgenticEngine.swift` if not already present.

### 9. Update `buildStablePrefix()` to use distilled variants

Replace the `buildStablePrefix()` implementation body so that when `promptCompressionEnabled`
is true it substitutes the distilled variants:

```swift
func buildStablePrefix() -> String {
    if !_stablePrefixDirty {
        return _stablePrefixCached
    }
    let compressionEnabled = AppSettings.shared.promptCompressionEnabled
    var parts: [String] = []

    // constitution.md: use distilled version when compression is on and distillation has run.
    if !constitutionContent.isEmpty {
        let mdToUse = compressionEnabled && !constitutionDistilledContent.isEmpty
            ? constitutionDistilledContent
            : constitutionContent
        parts.append(mdToUse)
    }
    if !memoriesContent.isEmpty {
        parts.append(memoriesContent)
    }
    if permissionMode == .plan {
        parts.append(PermissionMode.planSystemPrompt)
    }
    if let path = currentProjectPath {
        parts.append("Working directory: \(path)\nAlways use this path when accessing project files unless the user specifies otherwise.")
    }

    // Core system prompt: use distilled version when compression is on.
    let corePrompt = compressionEnabled
        ? AgenticEngine.distilledCoreSystemPrompt
        : AgenticEngine.coreSystemPrompt
    parts.append(corePrompt)

    if !standingInstructions.isEmpty {
        parts.append(standingInstructions)
    }
    _stablePrefixCached = parts.joined(separator: "\n\n")
    _stablePrefixDirty = false
    return _stablePrefixCached
}
```

### 10. Invalidate prefix cache when compression setting changes

`promptCompressionEnabled` is not currently observed by `_stablePrefixDirty`. Add a property
observer in `AppState` (or wherever `engine.constitutionContent` is set) that sets
`engine._stablePrefixDirty = true` when `AppSettings.shared.promptCompressionEnabled` changes.
The simplest approach: in `AppState.init()` or its settings-observation block, add:

```swift
// Invalidate the stable prefix cache when prompt compression is toggled.
settings.$promptCompressionEnabled
    .sink { [weak self] _ in self?.engine._stablePrefixDirty = true }
    .store(in: &cancellables)
```

If `AppState` already observes `AppSettings` via Combine for other properties, add this alongside them.
If not, a simpler alternative is to make `buildStablePrefix()` always include `promptCompressionEnabled`
in its dirty-check by reading `AppSettings.shared.promptCompressionEnabled` directly inside the guard —
but since `_stablePrefixDirty = true` is set by `didSet` on `constitutionContent`, the cache will be
invalidated anyway the next time constitution.md reloads. For Settings toggle take effect immediately,
the Combine sink is preferred.

---

## Add to: Merlin/UI/Settings/AgentSettingsView.swift (or equivalent)

Add a toggle for `promptCompressionEnabled` in the Agent settings section:

```swift
Toggle("Prompt Compression", isOn: $settings.promptCompressionEnabled)
    .help("When enabled: uses a compact distilled version of the core system prompt, and compresses your constitution.md once per change. Reduces token cost of each LLM request.")
```

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: BUILD SUCCEEDED. All `InstructionDistillationTests` pass. No regressions in existing tests.

Manual verification:
1. Open a project with a large `constitution.md`.
2. Enable **Settings → Agent → Prompt Compression**.
3. Start a session — observe a one-time distillation delay (provider call).
4. Subsequent turns in the same session use the cached distilled constitution.md immediately.
5. Disable the toggle — the next session reverts to the full original constitution.md.
6. Edit `constitution.md` on disk — the next session detects the hash change and re-distils.

## Commit

```bash
git add Merlin/Config/AppSettings.swift \
        Merlin/Engine/AgenticEngine.swift \
        Merlin/UI/Settings/AgentSettingsView.swift
git commit -m "Task 207b — instruction distillation: distilled core prompt + cached constitution.md compression"
```
