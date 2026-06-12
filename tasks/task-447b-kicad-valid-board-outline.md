# Task 447b - KiCad-Valid Board Outline

Date: 2026-05-30

## Goal

Make runtime-generated board artifacts structurally valid for KiCad DRC without
claiming completed PCB placement or routing.

## Implementation Scope

1. Emit a minimal valid KiCad board document with canonical layers.
2. Add a closed rectangular `Edge.Cuts` outline.
3. Keep the board artifact honest: no fabricated placements, routes, or copper
   evidence.
4. Use this minimal board path for generic compile output until real placement
   and routing exists.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/FullGreenRuntimeElectronicsTests
```

Expected after Task 447b: focused runtime board output is DRC-clean for outline
validity when real KiCad is available.
