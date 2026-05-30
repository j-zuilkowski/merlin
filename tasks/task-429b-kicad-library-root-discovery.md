# Task 429b - KiCad Library Root Discovery

Date: 2026-05-30

## Goal

Implement generic KiCad library root discovery for local symbol and footprint
catalog extraction.

## Implementation Scope

1. Search configured and common KiCad install roots.
2. Detect `symbols` and `footprints` layouts below app/support directories.
3. Return nil when roots are incomplete.
4. Keep discovery in electronics catalog support code.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ComponentCatalogContractsTests
```

Expected after Task 429b: configured KiCad library roots are discovered.
