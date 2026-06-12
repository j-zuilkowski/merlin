# Task 414a - Electronics Runtime Evidence Pipeline Tests

## Goal

Add focused tests proving compile-time evidence gates report the next concrete
pipeline step instead of a generic continuation action.

## Failing Tests

Add focused tests proving:

1. Missing Circuit IR returns `generate_circuit_ir`.
2. Missing ComponentMatrix returns `select_components`.
3. Missing footprint assignment returns `assign_footprints`.
4. Invalid or incomplete footprint evidence returns the same footprint repair
   action instead of advancing compile.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/CompileGateEvidenceTests
```

Expected: tests fail before Task 414b.
