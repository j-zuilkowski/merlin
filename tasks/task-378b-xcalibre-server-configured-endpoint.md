# Task 378b - xcalibre-server Configured Endpoint Implementation

## Traceability

- Vision reference: vision.md#rag-and-grounding-must-use-configured-local-services
- Spec reference: spec.md#xcalibre-server-rag-integration
- Tests: tasks/task-378a-xcalibre-server-configured-endpoint-tests.md

## Behavior

WHEN task 378b is executed THE system SHALL route Merlin RAG traffic through the configured `xcalibre-server` endpoint.
WHEN `AppSettings.kagXcalibreURL` is present THE system SHALL pass that URL into `XcalibreClient` during `AppState` initialization.
WHEN `AppSettings.kagXcalibreURL` is empty THE system SHALL preserve the existing environment/default endpoint fallback.

Implementation requirements:

- Add a small test accessor to `XcalibreClient` for its configured base URL.
- In `AppState.init`, pass `AppSettings.shared.kagXcalibreURL` to `XcalibreClient` when non-empty.
- Preserve the existing default environment/config fallback when the setting is empty.

## Verify

```sh
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= \
  -only-testing:MerlinTests/AppStateXcalibreServerEndpointTests
```
