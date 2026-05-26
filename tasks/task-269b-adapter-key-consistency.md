# Task 269b — Adapter Key Consistency

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 269a complete: failing test for adapter-key lookup.

This task makes `AdapterRegistry.loadFromDirectory` register adapters under the TOML
filename stem (the adapter-key) so `registry.adapter(for: config.adapter)` resolves for
real projects, where `config.adapter` is `"swift-xcode"` / `"rust-cargo"`.

---

## Edit: Merlin/Discipline/AdapterRegistry.swift

In `loadFromDirectory(_:)`, register each adapter under the filename stem instead of
`adapter.language`.

```swift
// Before:
        for file in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where file.pathExtension == "toml" {
            let text = try String(contentsOf: file, encoding: .utf8)
            do {
                let adapter = try TOMLAdapterParser.parse(text)
                adapters[adapter.language] = adapter
            } catch {

// After:
        for file in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where file.pathExtension == "toml" {
            let text = try String(contentsOf: file, encoding: .utf8)
            do {
                let adapter = try TOMLAdapterParser.parse(text)
                // Register under the filename stem (the adapter-key, e.g.
                // "swift-xcode"). ProjectConfig.adapter from .merlin/project.toml uses
                // that key, NOT the bare language, so keying by language here would
                // make adapter(for: config.adapter) throw notFound for every project.
                let key = file.deletingPathExtension().lastPathComponent
                adapters[key] = adapter
            } catch {
```

`register(_:for:)` and `adapter(for:)` are unchanged — explicit-key registration still
works, and the seed install path (`installSeedAdapters`) already writes
`swift-xcode.toml` / `rust-cargo.toml`.

---

## Regression note — task 241 adapter tests

`loadFromDirectory` previously keyed by `adapter.language`, so existing tests that load
seed/fixture adapters and then look them up by `"swift"` / `"rust"` will now fail —
those keys no longer exist after a directory load. Before committing, the implementer
MUST check the following two files and update any assertion that calls
`adapter(for: "swift")` / `adapter(for: "rust")` *after a `loadFromDirectory` call* to
use `adapter(for: "swift-xcode")` / `adapter(for: "rust-cargo")`:

- `MerlinTests/Unit/AdapterRegistryTests.swift`
- `MerlinTests/Unit/AdapterSeedTests.swift`

Specifically, `AdapterSeedTests.testSeedAdaptersLoadCorrectLanguages` and
`testSeedAdaptersHaveManualCoveragePatterns` call `registry.adapter(for: "swift")` and
`registry.adapter(for: "rust")` after `loadFromDirectory` — change those to
`"swift-xcode"` and `"rust-cargo"`. Do NOT change tests that use `register(_:for:)`
directly with an explicit key (e.g. `AdapterRegistryTests.testRegisterAndRetrieve`,
`testRegisterOverwrites`, `testNotFoundThrows`, `testLoadFromDirectory` with its
`haskell.toml` fixture — that one's stem is `"haskell"` which equals its language, so it
still passes). List every test file actually modified in the commit's `git add`.

---

## Fixes

- `AdapterRegistry.loadFromDirectory` registers each adapter under the TOML filename
  stem (adapter-key) instead of `adapter.language`. This makes
  `registry.adapter(for: config.adapter)` resolve, since `ProjectConfig.adapter` carries
  the adapter-key.
- `AdapterSeedTests` post-load lookups updated from language keys to adapter-keys.

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40

xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED** and all task 269a tests pass. The updated
`AdapterSeedTests` assertions pass with the new keys. No other prior task regresses.

## Commit

```bash
git add tasks/task-269b-adapter-key-consistency.md \
    Merlin/Discipline/AdapterRegistry.swift \
    MerlinTests/Unit/AdapterSeedTests.swift
git commit -m "Task 269b — AdapterRegistry key consistency"
```

If `AdapterRegistryTests.swift` also required changes, add it to the `git add` list above.
