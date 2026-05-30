# Task 388a - UI runner bootstrap tests

## Traceability

- Vision reference: vision.md#macos-native-app-experience
- Spec reference: spec.md#full-green-e2e-battery-v24
- Prior failure: full `MerlinUITests` and focused `VisualLayoutTests` crashed before XCTest automation bootstrapped under `/tmp/merlin-e2e-derived` with code signing disabled, while focused visual tests passed under default DerivedData.

## Behavior

WHEN the full GUI battery starts THE runner SHALL use a documented supported DerivedData and signing mode that can establish the XCTest automation connection.
WHEN a requested GUI runner mode is unsupported THE runner SHALL fail during preflight with a clear configuration error before launching XCTest.
WHEN focused visual tests run THE focused command SHALL use the same bootstrapping contract as the full GUI target.

## Red Tests

- Add a preflight unit or script test that models the `/tmp` no-signing GUI runner mode and asserts it is either supported explicitly or rejected before XCTest launch.
- Add coverage that the full UI command and focused `VisualLayoutTests` command share the same DerivedData/signing bootstrap policy.
- Add failure-message coverage for early XCTest runner exits so reports identify runner bootstrap separately from app/test failures.

## Verification

```bash
xcodegen generate
xcodebuild -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/UIRunnerBootstrapPolicyTests test
```

Expected red state: the new bootstrap-policy tests fail because the current full battery can attempt an unsupported no-signing `/tmp` UI runner and crash before test execution.
