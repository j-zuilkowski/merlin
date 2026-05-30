# Task 382a — Chat accessibility identity tests

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview
- Prior failure: `VisualLayoutTests/testInputFieldExists`

## Behavior

WHEN the main chat and side chat are visible at the same time THE UI automation surface SHALL expose unique accessibility identifiers for each chat surface.

GIVEN a workspace session has both chat surfaces available,
WHEN XCTest queries for the main chat input,
THEN the query SHALL match exactly one enabled element.

GIVEN the side chat is open,
WHEN XCTest queries for side-chat controls,
THEN the side-chat input, attachment, voice, send, and cancel controls SHALL use
side-chat-specific identifiers and SHALL NOT collide with the main chat.

## Red Tests

- Extend `VisualLayoutTests` or add a focused UI test that opens a test project,
  enables side chat, and asserts:
  - `chat-input` resolves to exactly one main-chat text field;
  - `side-chat-input` resolves to exactly one side-chat text field;
  - attachment, voice, send, and cancel button identifiers are also unique per
    chat surface.
- Keep the test strict: do not weaken it by accepting multiple matching
  `chat-input` fields.

## Verification

```bash
xcodegen generate
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests-Live \
  -destination 'platform=macOS' \
  -only-testing:MerlinUITests/VisualLayoutTests/testInputFieldExists
```

Expected red state: the query is ambiguous while multiple chat surfaces reuse
`chat-input`.
