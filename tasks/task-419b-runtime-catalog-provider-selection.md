# Task 419b - Runtime Catalog Provider Selection

## Goal

Wire catalog provider adapters into `kicad_select_components` so runtime
selection can use configured provider evidence instead of requiring a manually
materialized candidate file.

## Implementation

1. Read optional recorded provider fixture paths from the tool payload.
2. Map known provider fixture responses through the plugin-owned adapters.
3. Merge provider candidates with explicit `catalog_candidates_path` evidence.
4. Match candidates to Circuit IR-derived component requests by concrete class.
5. Preserve provider/cache metadata in `ComponentMatrix.cache_metadata`.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests
```

Expected: tests pass.
