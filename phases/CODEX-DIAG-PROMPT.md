# Single-Shot Codex Prompt — Build All Diag Phases

Paste the following block verbatim as the Codex task prompt.

---

```
You are building the diagnostics/telemetry system for the Merlin macOS SwiftUI app.
Working directory: ~/Documents/localProject/merlin

Rules (non-negotiable):
- Swift 5.10, macOS 14+, SWIFT_STRICT_CONCURRENCY=complete
- Zero warnings, zero errors after every phase
- TDD: phase NNa writes failing tests, NNb makes them pass — commit after each phase
- Never use git add -A; always add specific files
- Never skip the commit step

Execute ALL of the following phases in order. For each phase:
  1. Read the phase file from phases/
  2. Write/edit exactly the files listed in that phase
  3. Run the verify command and confirm the expected result
  4. Run the commit command

---

PHASE diag-01a — Read phases/diag-01a-telemetry-emitter-tests.md
Write: MerlinTests/Unit/TelemetryEmitterTests.swift
Verify: xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived 2>&1 | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
Expected: BUILD FAILED (TelemetryEmitter not found)
Commit: git add MerlinTests/Unit/TelemetryEmitterTests.swift && git commit -m "Phase diag-01a — TelemetryEmitter tests (failing)"

PHASE diag-01b — Read phases/diag-01b-telemetry-emitter.md
Write: Merlin/Telemetry/TelemetryEmitter.swift
Run xcodegen generate (project.yml already includes Merlin/Telemetry if present as a glob; confirm or add if needed)
Verify: xcodebuild -scheme MerlinTests test -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived 2>&1 | grep -E 'TelemetryEmitter|passed|failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
Expected: BUILD SUCCEEDED, all TelemetryEmitterTests pass
Commit: git add Merlin/Telemetry/TelemetryEmitter.swift project.yml Merlin.xcodeproj && git commit -m "Phase diag-01b — TelemetryEmitter core"

PHASE diag-02a — Read phases/diag-02a-provider-telemetry-tests.md
Write: MerlinTests/Unit/ProviderTelemetryTests.swift
Verify: xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived 2>&1 | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
Expected: BUILD FAILED (session: param missing, telemetry events absent)
Commit: git add MerlinTests/Unit/ProviderTelemetryTests.swift && git commit -m "Phase diag-02a — Provider telemetry tests (failing)"

PHASE diag-02b — Read phases/diag-02b-provider-telemetry.md
Replace entire files:
  Merlin/Providers/OpenAICompatibleProvider.swift
  Merlin/Providers/DeepSeekProvider.swift
Verify: xcodebuild -scheme MerlinTests test -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived 2>&1 | grep -E 'ProviderTelemetry|passed|failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
Expected: BUILD SUCCEEDED, all ProviderTelemetryTests pass
Commit: git add Merlin/Providers/OpenAICompatibleProvider.swift Merlin/Providers/DeepSeekProvider.swift && git commit -m "Phase diag-02b — Provider telemetry instrumentation"

PHASE diag-03a — Read phases/diag-03a-engine-telemetry-tests.md
Write: MerlinTests/Unit/EngineTelemetryTests.swift
Verify: xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived 2>&1 | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
Expected: BUILD FAILED (engine telemetry events absent, setRegistryForTesting missing)
Commit: git add MerlinTests/Unit/EngineTelemetryTests.swift && git commit -m "Phase diag-03a — Engine telemetry tests (failing)"

PHASE diag-03b — Read phases/diag-03b-engine-telemetry.md
Edit: Merlin/Engine/AgenticEngine.swift
  - Add setRegistryForTesting() helper
  - Emit engine.turn.start + engine.provider.selected in send()
  - Emit engine.turn.complete + engine.turn.error in runLoop()
  - Emit engine.tool.dispatched + engine.tool.complete + engine.tool.error in tool dispatch loop
Verify: xcodebuild -scheme MerlinTests test -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived 2>&1 | grep -E 'EngineTelemetry|passed|failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
Expected: BUILD SUCCEEDED, all EngineTelemetryTests pass
Commit: git add Merlin/Engine/AgenticEngine.swift && git commit -m "Phase diag-03b — Engine telemetry instrumentation"

PHASE diag-04a — Read phases/diag-04a-memory-telemetry-tests.md
Write: MerlinTests/Unit/MemoryTelemetryTests.swift
       MerlinTests/Unit/RAGTelemetryTests.swift
Verify: xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived 2>&1 | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
Expected: BUILD FAILED (memory/RAG telemetry events absent)
Commit: git add MerlinTests/Unit/MemoryTelemetryTests.swift MerlinTests/Unit/RAGTelemetryTests.swift && git commit -m "Phase diag-04a — Memory & RAG telemetry tests (failing)"

PHASE diag-04b — Read phases/diag-04b-memory-telemetry.md
Edit: Merlin/Memories/MemoryEngine.swift
      Merlin/RAG/XcalibreClient.swift
Verify: xcodebuild -scheme MerlinTests test -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived 2>&1 | grep -E 'MemoryTelemetry|RAGTelemetry|passed|failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
Expected: BUILD SUCCEEDED, all MemoryTelemetryTests and RAGTelemetryTests pass
Commit: git add Merlin/Memories/MemoryEngine.swift Merlin/RAG/XcalibreClient.swift && git commit -m "Phase diag-04b — Memory & RAG telemetry instrumentation"

PHASE diag-05a — Read phases/diag-05a-context-planner-critic-tests.md
Write: MerlinTests/Unit/ContextCompactionTelemetryTests.swift
       MerlinTests/Unit/PlannerTelemetryTests.swift
       MerlinTests/Unit/CriticTelemetryTests.swift
Verify: xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived 2>&1 | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
Expected: BUILD FAILED (context.compaction, planner.classify, critic.evaluate.start events absent)
Commit: git add MerlinTests/Unit/ContextCompactionTelemetryTests.swift MerlinTests/Unit/PlannerTelemetryTests.swift MerlinTests/Unit/CriticTelemetryTests.swift && git commit -m "Phase diag-05a — Context, planner & critic telemetry tests (failing)"

PHASE diag-05b — Read phases/diag-05b-context-planner-critic.md
Edit: Merlin/Engine/ContextManager.swift
      Merlin/Engine/PlannerEngine.swift
      Merlin/Engine/CriticEngine.swift
Verify: xcodebuild -scheme MerlinTests test -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived 2>&1 | grep -E 'ContextCompaction|PlannerTelemetry|CriticTelemetry|passed|failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
Expected: BUILD SUCCEEDED, all new tests pass
Commit: git add Merlin/Engine/ContextManager.swift Merlin/Engine/PlannerEngine.swift Merlin/Engine/CriticEngine.swift && git commit -m "Phase diag-05b — Context, planner & critic telemetry instrumentation"

PHASE diag-06a — Read phases/diag-06a-infra-telemetry-tests.md
Write: MerlinTests/Unit/SessionStoreTelemetryTests.swift
       MerlinTests/Unit/HookTelemetryTests.swift
       MerlinTests/Unit/ProcessMemoryTelemetryTests.swift
Verify: xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived 2>&1 | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
Expected: BUILD FAILED (session.save, hook.pre_tool, process.memory events absent; emitProcessMemory missing)
Commit: git add MerlinTests/Unit/SessionStoreTelemetryTests.swift MerlinTests/Unit/HookTelemetryTests.swift MerlinTests/Unit/ProcessMemoryTelemetryTests.swift && git commit -m "Phase diag-06a — Infrastructure telemetry tests (failing)"

PHASE diag-06b — Read phases/diag-06b-infra-telemetry.md
Edit: Merlin/Telemetry/TelemetryEmitter.swift   (add emitProcessMemory())
      Merlin/Sessions/SessionStore.swift
      Merlin/Hooks/HookEngine.swift
      Merlin/MCP/MCPBridge.swift
Verify: xcodebuild -scheme MerlinTests test -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived 2>&1 | grep -E 'SessionStore|HookTelemetry|ProcessMemory|passed|failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
Expected: BUILD SUCCEEDED, all new tests pass
Commit: git add Merlin/Telemetry/TelemetryEmitter.swift Merlin/Sessions/SessionStore.swift Merlin/Hooks/HookEngine.swift Merlin/MCP/MCPBridge.swift && git commit -m "Phase diag-06b — Infrastructure telemetry instrumentation"

PHASE diag-07a — Read phases/diag-07a-accessibility-tests.md
Write: MerlinTests/Unit/AccessibilityIDTests.swift
       MerlinTests/Unit/GUIActionTelemetryTests.swift
Verify: xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived 2>&1 | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
Expected: BUILD FAILED (AccessibilityID enum missing; emitGUIAction missing)
Commit: git add MerlinTests/Unit/AccessibilityIDTests.swift MerlinTests/Unit/GUIActionTelemetryTests.swift && git commit -m "Phase diag-07a — Accessibility identifier tests (failing)"

PHASE diag-07b — Read phases/diag-07b-accessibility.md
Write: Merlin/Support/AccessibilityID.swift
Edit:  Merlin/Telemetry/TelemetryEmitter.swift   (add emitGUIAction())
       Merlin/Views/ChatView.swift
       Merlin/Views/SessionSidebar.swift
       Merlin/Views/ProviderHUD.swift
       Merlin/Views/ContentView.swift
Verify: xcodebuild -scheme MerlinTests test -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived 2>&1 | grep -E 'AccessibilityID|GUIAction|passed|failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
Expected: BUILD SUCCEEDED, all AccessibilityIDTests and GUIActionTelemetryTests pass, zero warnings
Commit: git add Merlin/Support/AccessibilityID.swift Merlin/Telemetry/TelemetryEmitter.swift Merlin/Views/ChatView.swift Merlin/Views/SessionSidebar.swift Merlin/Views/ProviderHUD.swift Merlin/Views/ContentView.swift && git commit -m "Phase diag-07b — Accessibility identifiers and GUI action telemetry"

---

FINAL CHECK after all phases:
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived 2>&1 | grep -E 'passed|failed|BUILD SUCCEEDED|BUILD FAILED' | tail -20

All tests must pass. BUILD SUCCEEDED. Zero warnings. Zero errors.
If any phase fails, fix it before proceeding — do not skip phases.
```
