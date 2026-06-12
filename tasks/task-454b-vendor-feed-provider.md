# Task 454b - Vendor Feed Provider

Status: complete

Objective: Implement a local `vendor_feed` catalog provider as the non-scraping alternative for distributor/aggregator evidence when API access is unavailable.

Implementation notes:
- Added `VendorFeedCatalogProviderAdapter` for user-supplied CSV and JSON files.
- Added runtime support for `vendor_feed_paths` in payloads and electronics provider config.
- Added fixture routing for `catalog_provider_fixture_paths.vendor_feed`.
- Added plugin-owned `catalog_provider_vendor_feed_enabled`, default enabled.
- Added Provider Settings entry with no credentials button because the provider is local-file only.

Constraints:
- No scraping.
- No hidden web discovery.
- No live network calls.
- Feed files must be explicitly supplied by path.
- Component selection still requires the existing evidence gates to pass.

Verification:
- `xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/RealCatalogProviderAdaptersTests`
- Result: TEST SUCCEEDED, 15 tests, 0 failures.
