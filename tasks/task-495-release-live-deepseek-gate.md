# Task 495 - Release Live DeepSeek Gate

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#spec-driven-development-methodology

## Behavior

WHEN the v2.4.0 release ledger reaches the live-provider gate THE workflow
SHALL run the DeepSeek-backed live provider and agent-loop slice when a
DeepSeek key is available through the supported environment/key-store paths.

WHEN the required live key is unavailable THE ledger SHALL use
`skipped-with-evidence` and name the missing key source instead of reporting a
pass.

WHEN the live provider or agent-loop slice fails THE workflow SHALL preserve the
failure log and keep post-green screenshot gates blocked.

## Goal

Run release gate #4 without running the full AmpDemo GUI demo or unrelated
post-green screenshot work.

## Evidence

- Fail-first: `docs/e2e/2026-06-08-v2.4.0-release/logs/04-MerlinTests-Live.fail-first.log`
  recorded the first gate #4 run failing at compile with
  `CalibrationLiveTests.swift:72:13: error: switch must be exhaustive`;
  missing case `.llamaCppRuntimeUntuned`.
- Running target: `xcodebuild test -project Merlin.xcodeproj -scheme
  MerlinTests-Live -destination 'platform=macOS' -derivedDataPath
  /tmp/merlin-derived-v240-live-deepseek
  -only-testing:MerlinLiveTests/DeepSeekProviderLiveTests
  -only-testing:MerlinE2ETests/AgenticLoopE2ETests`.
- Green: `docs/e2e/2026-06-08-v2.4.0-release/logs/04-MerlinTests-Live.log`
  records `TEST SUCCEEDED`; `DeepSeekProviderLiveTests` passed 3 tests and
  `AgenticLoopE2ETests/testFullLoopWithRealDeepSeek` passed 1 test, 0
  failures. Xcresult:
  `/tmp/merlin-derived-v240-live-deepseek/Logs/Test/Test-MerlinTests-Live-2026.06.08_15-13-52--0400.xcresult`.
