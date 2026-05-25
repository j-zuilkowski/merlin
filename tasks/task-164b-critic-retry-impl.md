# Phase 164b — Critic Retry Loop Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 164a complete: failing tests in MerlinTests/Unit/AgenticEngineCriticRetryTests.swift.

---

## Changes

### 1. AppSettings.swift — add criticEnabled + maxCriticRetries

Add two `@Published` properties after `maxPlanRetries` / `maxLoopIterations` (~line 96):

```swift
    @Published var maxLoopIterations: Int = 100
    /// TOML key `critic_enabled`. Default: `true`. Set to false to disable critic entirely.
    @Published var criticEnabled: Bool = true
    /// TOML key `max_critic_retries`. Default: `2`. Max times engine retries after critic fail.
    @Published var maxCriticRetries: Int = 2
```

In `ConfigFile` struct, add inside the `PlannerConfig` struct (or as a new `CriticConfig` struct):

Add a new `CriticConfig` struct inside `ConfigFile`:
```swift
        struct CriticConfig: Codable, Sendable {
            var criticEnabled: Bool?
            var maxCriticRetries: Int?

            enum CodingKeys: String, CodingKey {
                case criticEnabled = "critic_enabled"
                case maxCriticRetries = "max_critic_retries"
            }
        }
```

Add the property to `ConfigFile`:
```swift
        var critic: CriticConfig?
```

In `apply(to settings:)` (or wherever ConfigFile fields are mapped to AppSettings), add:
```swift
        if let critic = critic {
            if let v = critic.criticEnabled { settings.criticEnabled = v }
            if let v = critic.maxCriticRetries { settings.maxCriticRetries = v }
        }
```

In `from(settings:)` (serialization), add:
```swift
        critic = CriticConfig(
            criticEnabled: settings.criticEnabled == true ? nil : settings.criticEnabled,
            maxCriticRetries: settings.maxCriticRetries == 2 ? nil : settings.maxCriticRetries
        )
```
(Omit from TOML when at default values to keep config files clean.)

---

### 2. AgenticEngine.swift — critic retry loop + OutcomeSignals wiring

**Step A — Add per-turn counters before the `while true` loop**

Near line 614, after the existing per-turn local vars (`lastResponseText`, `capturedFinishReason`, etc.),
add:

```swift
        var criticRetryCount = 0
        var finalCriticResult: CriticResult? = nil
```

**Step B — Replace the critic block (lines ~730–763) with the retry-aware version**

Find this section (inside the `guard sawToolCall` else branch, before the hook check):

```swift
                    let isSubstantialOutput = fullText.count > 1500
                    let shouldRunCritic = !writtenFilePaths.isEmpty || isSubstantialOutput ||
                        (classification.complexity != .routine &&
                         (classifierOverride != nil || classification.complexity == .highStakes))
                    if shouldRunCritic {
                        if let reasonProvider = self.provider(for: .reason),
                           !(reasonProvider is NullProvider) {
                            let critic = makeCritic(domain: domain)
                            let taskType = domain.taskTypes.first
                                ?? DomainTaskType(domainID: domain.id, name: "general", displayName: "General")
                            let verdict = await critic.evaluate(
                                taskType: taskType,
                                output: fullText,
                                context: context.messages,
                                writtenFiles: writtenFilePaths
                            )
                            lastCriticVerdict = verdict
                            switch verdict {
                            case .pass, .skipped:
                                consecutiveCriticFailures = 0
                            case .fail:
                                consecutiveCriticFailures += 1
                            }
                            switch verdict {
                            case .pass:
                                break
                            case .fail(let reason):
                                continuation.yield(.systemNote("[Critic: \(reason)]"))
                            case .skipped:
                                continuation.yield(.systemNote("[unverified — critic unavailable]"))
                            }
                        } else {
                            continuation.yield(.systemNote("[unverified — critic unavailable]"))
                        }
                    }
```

Replace with:

```swift
                    let isSubstantialOutput = fullText.count > 1500
                    let shouldRunCritic = !writtenFilePaths.isEmpty || isSubstantialOutput ||
                        (classification.complexity != .routine &&
                         (classifierOverride != nil || classification.complexity == .highStakes))
                    let criticIsEnabled = await MainActor.run { AppSettings.shared.criticEnabled }
                    if shouldRunCritic && criticIsEnabled {
                        if let reasonProvider = self.provider(for: .reason),
                           !(reasonProvider is NullProvider) {
                            let critic = makeCritic(domain: domain)
                            let taskType = domain.taskTypes.first
                                ?? DomainTaskType(domainID: domain.id, name: "general", displayName: "General")
                            let maxRetries = await MainActor.run { AppSettings.shared.maxCriticRetries }
                            let verdict = await critic.evaluate(
                                taskType: taskType,
                                output: fullText,
                                context: context.messages,
                                writtenFiles: writtenFilePaths
                            )
                            lastCriticVerdict = verdict
                            finalCriticResult = verdict
                            switch verdict {
                            case .pass, .skipped:
                                consecutiveCriticFailures = 0
                            case .fail:
                                consecutiveCriticFailures += 1
                            }
                            switch verdict {
                            case .pass:
                                break
                            case .fail(let reason):
                                if criticRetryCount < maxRetries {
                                    // Inject correction as a user message and re-run the worker
                                    criticRetryCount += 1
                                    context.append(Message(
                                        role: .user,
                                        content: .text(
                                            "[Critic correction (\(criticRetryCount)/\(maxRetries)): \(reason). Please address this issue and provide a corrected response.]"
                                        ),
                                        timestamp: Date()
                                    ))
                                    continue  // re-enter while loop — worker generates corrected output
                                } else {
                                    continuation.yield(.systemNote(
                                        "[Critic: max retries (\(maxRetries)) exhausted — \(reason)]"
                                    ))
                                }
                            case .skipped:
                                continuation.yield(.systemNote("[unverified — critic unavailable]"))
                            }
                        } else {
                            continuation.yield(.systemNote("[unverified — critic unavailable]"))
                        }
                    }
```

**Step C — Wire OutcomeSignals from finalCriticResult (lines ~924–934)**

Find:
```swift
        let signals = OutcomeSignals(
            stage1Passed: nil,
            stage2Score: nil,
            diffAccepted: stagingRejected == 0 || stagingAccepted > 0,
            diffEditedOnAccept: stagingEdited > 0,
            criticRetryCount: 0,
            userCorrectedNextTurn: false,
            sessionCompleted: true,
            addendumHash: await currentAddendumHash(for: workingSlot),
            finishReason: capturedFinishReason
        )
```

Replace with:
```swift
        // Derive stage1Passed from the final critic verdict:
        //   .pass  → true   (verification succeeded — either stage1 or stage2 passed)
        //   .fail  → false  (retries exhausted with no pass)
        //   .skipped → nil  (no verification backend or critic disabled)
        //   nil (critic never ran) → nil
        let stage1PassedSignal: Bool? = {
            switch finalCriticResult {
            case .pass:   return true
            case .fail:   return false
            case .skipped, nil: return nil
            }
        }()
        let signals = OutcomeSignals(
            stage1Passed: stage1PassedSignal,
            stage2Score: nil,
            diffAccepted: stagingRejected == 0 || stagingAccepted > 0,
            diffEditedOnAccept: stagingEdited > 0,
            criticRetryCount: criticRetryCount,
            userCorrectedNextTurn: false,
            sessionCompleted: true,
            addendumHash: await currentAddendumHash(for: workingSlot),
            finishReason: capturedFinishReason
        )
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED, all AgenticEngineCriticRetryTests pass.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/Config/AppSettings.swift Merlin/Engine/AgenticEngine.swift
git commit -m "Phase 164b — Critic retry loop + OutcomeSignals wiring"
```
