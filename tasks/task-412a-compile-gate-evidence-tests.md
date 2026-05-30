# Task 412a — Compile Gate Evidence Tests

## Goal

Prevent skeleton KiCad files from being generated from intent-only or role-only
evidence.

## Failing Tests

Add focused tests proving:

1. Natural-language/electronics-generated designs cannot compile from
   `DesignIntent` alone.
2. Compile requires approved DesignIntent.
3. Compile requires Circuit IR.
4. Compile requires ComponentMatrix.
5. Compile requires footprint assignment for PCB-bound components.
6. Draft preview artifacts, if supported, cannot satisfy verified workflow
   statuses.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/CompileGateEvidenceTests
```

Expected: tests fail before Task 412b.
