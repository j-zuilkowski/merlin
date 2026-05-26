# Task 302a — Info.plist Permission Strings Tests (failing)

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.

A requirements audit found `Merlin/Info.plist` declares Accessibility, ScreenCapture, and
AppleEvents usage strings but is **missing** the Speech-recognition and microphone usage
strings. Voice dictation (`VoiceDictationEngine`, Speech framework + mic capture) is
therefore denied / can crash the app under hardened runtime. This task pins that gap;
task 302b fixes it. Prerequisite for the eval suite's voice-dictation scenario (S3).

New behaviour in task 302b: `Merlin/Info.plist` declares
`NSSpeechRecognitionUsageDescription` and `NSMicrophoneUsageDescription`.

TDD coverage:
  `MerlinTests/Unit/InfoPlistPermissionsTests.swift` — reads the app `Info.plist` from
  source and asserts both usage-description keys are present and non-empty.

## Write to: MerlinTests/Unit/InfoPlistPermissionsTests.swift

```swift
import XCTest

/// Task 302a — failing tests: the app Info.plist must declare the Speech and
/// microphone usage strings required for voice dictation under hardened runtime.
final class InfoPlistPermissionsTests: XCTestCase {

    /// Loads `Merlin/Info.plist` from the repo source tree, located relative to this
    /// test file (the test bundle's own Info.plist does not carry the app's keys).
    private func appInfoPlist() throws -> [String: Any] {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Unit
            .deletingLastPathComponent()   // MerlinTests
            .deletingLastPathComponent()   // repo root
        let plistURL = repoRoot.appendingPathComponent("Merlin/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return (plist as? [String: Any]) ?? [:]
    }

    func testInfoPlistDeclaresSpeechRecognitionUsage() throws {
        let value = try appInfoPlist()["NSSpeechRecognitionUsageDescription"] as? String
        XCTAssertNotNil(value, "Info.plist must declare NSSpeechRecognitionUsageDescription")
        XCTAssertFalse((value ?? "").isEmpty, "the usage string must be non-empty")
    }

    func testInfoPlistDeclaresMicrophoneUsage() throws {
        let value = try appInfoPlist()["NSMicrophoneUsageDescription"] as? String
        XCTAssertNotNil(value, "Info.plist must declare NSMicrophoneUsageDescription")
        XCTAssertFalse((value ?? "").isEmpty, "the usage string must be non-empty")
    }
}
```

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/InfoPlistPermissionsTests 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|error:'
```
Expected: BUILD SUCCEEDED; both tests FAIL (the keys are absent).

## Commit
```
git add MerlinTests/Unit/InfoPlistPermissionsTests.swift tasks/task-302a-info-plist-permissions-tests.md
git commit -m "Task 302a — Info.plist permission strings tests (failing)"
```
