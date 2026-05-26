# Task 378a - xcalibre-server Configured Endpoint Tests

## Traceability

- Vision reference: vision.md#rag-and-grounding-must-use-configured-local-services
- Spec reference: spec.md#xcalibre-server-rag-integration
- Evidence: docs/e2e/2026-05-26-merlin-full-gui/REPORT.md
- Failure: Merlin live RAG attempted the default loopback endpoint even when the test configured `xcalibre-server` at `127.0.0.1:8083`.

## Behavior

WHEN `AppSettings.kagXcalibreURL` is set THE system SHALL use that configured `xcalibre-server` endpoint for the book-content `XcalibreClient`, not only for KAG triple storage.
WHEN `AppSettings.kagXcalibreURL` is empty THE system SHALL preserve the existing environment/default `xcalibre-server` endpoint fallback.

## Tests

Add unit coverage:

- `AppState` initializes `xcalibreClient` with the configured `xcalibre-server` URL when set.
- Empty `kagXcalibreURL` still falls back to `XcalibreClient.defaultBaseURL()`.

## Verify

```sh
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= \
  -only-testing:MerlinTests/AppStateXcalibreServerEndpointTests
```
