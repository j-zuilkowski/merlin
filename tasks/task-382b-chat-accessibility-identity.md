# Task 382b — Chat accessibility identity

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview
- Test task: tasks/task-382a-chat-accessibility-identity-tests.md

## Behavior

WHEN Merlin renders more than one `ChatView` THE accessibility identifiers SHALL
be scoped to the surface that owns the controls.

GIVEN the main chat is visible,
WHEN automation queries main chat controls,
THEN the existing canonical identifiers SHALL continue to work for the main
surface.

GIVEN side chat is visible,
WHEN automation queries side-chat controls,
THEN side-chat-specific identifiers SHALL identify only side-chat controls.

## Implementation

- Add a chat accessibility scope to `ChatView` or its caller so identifiers are
  generated from the owning surface.
- Preserve existing main-chat identifiers for compatibility:
  `chat-input`, `chat-send-button`, `chat-cancel-button`,
  `chat-attachment-button`, and `chat-voice-button`.
- Add side-chat identifiers such as `side-chat-input`,
  `side-chat-send-button`, `side-chat-cancel-button`,
  `side-chat-attachment-button`, and `side-chat-voice-button`.
- Add constants in `AccessibilityID` and update tests that currently assume only
  one chat surface exists.

## Verification

```bash
xcodegen generate
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests-Live \
  -destination 'platform=macOS' \
  -only-testing:MerlinUITests/VisualLayoutTests/testInputFieldExists
```

Expected green state: the main chat input query is unambiguous and side-chat
controls are separately addressable.
