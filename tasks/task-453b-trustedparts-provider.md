# Task 453b: TrustedParts Provider

## Goal

Add TrustedParts as an optional, plugin-scoped catalog/BOM evidence provider for
authorized distributor data.

## Traceability

- Vision reference: vision.md#spec-driven-development-alignment
- Spec reference: spec.md#spec-driven-development-methodology

## Behavior

WHEN TrustedParts provider support is enabled THE electronics plugin SHALL use approved API credentials and preserve authorized distributor evidence.

## Constraints

1. Do not scrape TrustedParts pages.
2. Use only approved API credentials and HTTPS JSON POST.
3. Treat TrustedParts as catalog/BOM evidence only: stock, pricing, datasheet
   links, product links, descriptions, packaging, MOQ, lead time, and authorized
   distributor provenance.
4. Do not use TrustedParts for symbols, footprints, 3D models, circuit topology,
   analog design reasoning, or competitive analysis.
5. Keep the provider disabled by default and controlled by electronics plugin
   settings.
6. Cache normalized and raw responses with the existing live catalog TTL path.
7. Preserve the required evidence gate; missing package/datasheet/provenance
   must still block selection.

## Verify

Run task 453a and the focused AmpDemo live component-selection slice with
TrustedParts disabled unless credentials are explicitly configured.
