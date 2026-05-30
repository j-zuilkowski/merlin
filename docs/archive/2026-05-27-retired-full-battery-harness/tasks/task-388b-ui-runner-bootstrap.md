# Task 388b - UI runner bootstrap

## Traceability

- Vision reference: vision.md#macos-native-app-experience
- Spec reference: spec.md#full-green-e2e-battery-v24
- Test task: tasks/task-388a-ui-runner-bootstrap-tests.md

## Behavior

WHEN the full GUI battery invokes XCTest THE command SHALL use the supported UI runner mode documented by Merlin.
WHEN a custom DerivedData path or no-signing mode is requested THE preflight SHALL prove it can bootstrap or reject it before the XCTest run starts.
WHEN XCTest exits before automation bootstraps THE report SHALL classify the failure as runner bootstrap and include the command, DerivedData path, and signing settings.

## Implementation

- Document the supported GUI runner mode in the E2E harness scripts and local README.
- Add preflight checks for DerivedData location, app bundle path, UI test runner bundle, signing settings, and accessibility permissions.
- Align the full `MerlinUITests` command and focused `VisualLayoutTests` command so they use the same supported mode.
- If `/tmp` no-signing cannot be made reliable on macOS, make the harness reject it with actionable guidance instead of launching XCTest.
- Capture early runner bootstrap failures as a distinct report row.

## Verification

```bash
xcodegen generate
xcodebuild -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/UIRunnerBootstrapPolicyTests test
xcodebuild -scheme MerlinUITests -destination 'platform=macOS' test
xcodebuild -scheme MerlinUITests -destination 'platform=macOS' \
  -only-testing:MerlinUITests/VisualLayoutTests test
```

Expected green state: bootstrap-policy tests pass, the full UI target establishes XCTest automation, and focused visual tests pass under the same runner contract.
