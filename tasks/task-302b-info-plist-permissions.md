# Phase 302b — Info.plist Permission Strings (implementation)

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Phase 302a complete: failing tests in `InfoPlistPermissionsTests`.

## Edit: Merlin/Info.plist
Add the two usage-description keys inside the top-level `<dict>`, alongside the existing
`NSAccessibilityUsageDescription` / `NSScreenCaptureUsageDescription` entries:

```xml
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Merlin uses speech recognition to transcribe voice dictation into chat input.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Merlin uses the microphone to capture voice dictation.</string>
```

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/InfoPlistPermissionsTests
```
Expected: BUILD SUCCEEDED, both tests pass.

Runtime check: build + launch the app, trigger voice dictation (the mic button / Ctrl+M),
confirm macOS shows the Speech-recognition and microphone permission prompts with
Merlin's descriptions and that dictation works once granted.

## Commit
```
git add Merlin/Info.plist tasks/task-302b-info-plist-permissions.md
git commit -m "Phase 302b — Info.plist permission strings for voice dictation"
```
