# Task 454a - Vendor Feed Provider Tests

Status: complete

Objective: Add regression coverage for a local, user-supplied vendor feed catalog provider that does not scrape or call protected aggregator services.

Acceptance criteria:
- CSV exports map into strict component evidence: MPN, manufacturer, category, package, ratings, datasheet, provenance, distributor stock, MOQ, packaging, lead time, and lifecycle.
- JSON exports map into the same strict evidence shape.
- Runtime component selection can use `vendor_feed_paths` to satisfy evidence-gated selection without live catalog providers.
- Plugin settings schema exposes `catalog_provider_vendor_feed_enabled` under the electronics plugin namespace.

Verification:
- `xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' -only-testing:MerlinTests/ElectronicsPluginSchemaTests/testElectronicsPluginOwnsCatalogProviderSettingsSchema -only-testing:MerlinTests/RealCatalogProviderAdaptersTests/testVendorFeedAdapterMapsCSVExportIntoStrictEvidence -only-testing:MerlinTests/RealCatalogProviderAdaptersTests/testVendorFeedAdapterMapsJSONExportIntoStrictEvidence -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testVendorFeedPathProvidesLocalCatalogEvidenceForSelection`
- Result: TEST SUCCEEDED, 4 tests, 0 failures.
