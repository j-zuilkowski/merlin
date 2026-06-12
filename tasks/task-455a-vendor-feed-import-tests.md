# Task 455a - Vendor Feed Import Tests

Status: complete

Objective: Add regression coverage for importing user-supplied vendor feed files into the workspace cache.

Acceptance criteria:
- Import accepts explicit CSV/JSON paths only.
- Import copies feeds into `.merlin/electronics-vendor-feeds/`.
- Import updates `.merlin/electronics-provider-config.json` with `vendor_feed_paths`.
- Component selection can use the updated provider config without live vendor APIs.

Verification:
- `xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testVendorFeedImportCopiesFeedAndUpdatesProviderConfigForSelection`
