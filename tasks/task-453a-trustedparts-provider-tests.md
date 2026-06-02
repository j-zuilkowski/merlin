# Task 453a: TrustedParts Provider Tests

## Goal

Add regression coverage for TrustedParts as an optional electronics-plugin
catalog provider without weakening Merlin's evidence gate.

## Scope

1. TrustedParts settings are plugin-scoped and disabled by default.
2. TrustedParts recorded JSON maps into candidate evidence with authorized
   distributor stock, product links, datasheet links, packaging, MOQ, and
   provenance.
3. Live TrustedParts requests use HTTPS JSON POST, CompanyId, ApiKey, Queries,
   UserAgent, InStockOnly, ExactMatch, and one search token per component.
4. TrustedParts stays optional and is not queried when disabled.

## Verify

```sh
xcodebuild test -project Merlin.xcodeproj -scheme MerlinTests -destination 'platform=macOS' \
  -only-testing:MerlinTests/ElectronicsPluginSchemaTests/testElectronicsPluginOwnsCatalogProviderSettingsSchema \
  -only-testing:MerlinTests/RealCatalogProviderAdaptersTests/testTrustedPartsAdapterMapsAuthorizedInventoryEvidence \
  -only-testing:MerlinTests/RealCatalogProviderAdaptersTests/testLiveTrustedPartsProviderBuildsConservativeInventoryRequest \
  -only-testing:MerlinTests/EvidenceGatedComponentSelectionTests/testTrustedPartsDisabledPluginCatalogProviderIsNotQueriedEvenWhenRequested
```

Expected: `TEST SUCCEEDED`.
