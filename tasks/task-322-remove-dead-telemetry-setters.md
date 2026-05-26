# Task 322 — Remove Dead TelemetryEmitter Setters

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 321b complete: DocReferenceGraph comment-stripping fix landed.

W4 trace audit finding F5: `TelemetryEmitter.setSession(_:)`, `setTurn(_:)` and
`setLoop(_:)` are dead — a repo-wide grep finds **zero callers** in any target
(production, MerlinTests, MerlinLiveTests, MerlinE2ETests, TestHelpers). The only
context setter that is used is `setContext(sessionID:turn:loop:)` (test-only). The three
single-field setters are removed here.

This is an implementation-only cleanup task — pure dead-code removal, no new behavior,
so there is no `a` tests task. The compile gate is the verification: if anything
referenced the deleted methods, `build-for-testing` would fail.

---

## 1. Edit: Merlin/Telemetry/TelemetryEmitter.swift

Delete the three single-field setters and the blank line immediately above them. Change:
```swift
    public func setContext(sessionID: String, turn: Int, loop: Int) {
        self.sessionID = sessionID
        self.turn      = turn
        self.loop      = loop
    }

    public func setSession(_ id: String) { sessionID = id }
    public func setTurn(_ t: Int)        { turn = t }
    public func setLoop(_ l: Int)        { loop = l }

    // MARK: Emit
```
to:
```swift
    public func setContext(sessionID: String, turn: Int, loop: Int) {
        self.sessionID = sessionID
        self.turn      = turn
        self.loop      = loop
    }

    // MARK: Emit
```

## 2. Edit: tasks/diag-01b-telemetry-emitter.md

`diag-01b` is the rebuild source of truth for `TelemetryEmitter`. Make the identical
deletion in its `Write to: Merlin/Telemetry/TelemetryEmitter.swift` code block — remove
the same three `setSession` / `setTurn` / `setLoop` lines and the blank line above them.

Then add this `## Fixes` section at the end of `diag-01b-telemetry-emitter.md`:
```
## Fixes
Task 322 removed `setSession(_:)`, `setTurn(_:)` and `setLoop(_:)` — dead code with
zero callers in any target (W4 trace-audit finding F5). `setContext(sessionID:turn:loop:)`
is the surviving context setter.
```

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/TelemetryEmitterTests 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|error:'
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
xcodebuild -scheme MerlinTests-Live build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
  | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: `TelemetryEmitterTests` still passes; BUILD SUCCEEDED on both schemes, zero
warnings. (A BUILD FAILED here would mean some target referenced a deleted setter — it
does not; the grep confirmed zero callers.)

## Commit
```
git add Merlin/Telemetry/TelemetryEmitter.swift tasks/diag-01b-telemetry-emitter.md tasks/task-322-remove-dead-telemetry-setters.md
git commit -m "Task 322 — Remove dead TelemetryEmitter setters"
```
