# S2 Rerun - 2026-05-26

## Result

S2 now passes in isolation with the requested live-provider shape:

- one local llama.cpp router server for the execute/vision pair
- DeepSeek for reason/orchestrate/critic
- real sibling `xcalibre-server` on `127.0.0.1:8083`

The successful XCTest completed in 269.698 seconds with 0 failures.

Command shape:

```sh
xcodebuild -scheme MerlinTests-Live test \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-e2e-derived \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= \
  -only-testing:MerlinE2ETests/CapabilityScenarioTests/testS2RustDebugCycle
```

## Services

- llama.cpp router was started on `127.0.0.1:8081` with `llamacpp-router-models.ini`.
- xcalibre-server was built from `/Users/jonzuilkowski/Documents/localProject/xcalibre-server` and started on `127.0.0.1:8083`.
- Merlin was temporarily configured to use `http://127.0.0.1:8083` as the xcalibre-server endpoint.
- No IPv6 proxy was required for the passing run.

## Fixes Proven By This Rerun

1. Project-root scoped tools now resolve empty, relative, and `.` paths against the active project root instead of the Merlin source repo.
2. Merlin now passes the configured xcalibre-server endpoint into the RAG client used during live execution.
3. llama.cpp context-overrun responses are classified as context limit failures, and the test router preset uses a larger local context.
4. The default planner loop ceiling is bounded to 10 iterations, matching the serialized default and preventing small live tasks from running indefinitely.

## Passing Evidence

Primary XCTest evidence:

```text
Test Case '-[MerlinE2ETests.CapabilityScenarioTests testS2RustDebugCycle]' passed (269.698 seconds).
Executed 1 test, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
```

Generated harness result:

```text
merlin-eval/results/S2-harness-2026-05-26T15-44-02Z.md
```

The harness result shows the Rust fixture was repaired:

```text
cargo test ... ok
5 unit tests passed
1 CLI test passed
```

The CLI verification also succeeded:

```text
cargo run --bin ledger-cli -- add 1200 food
cargo run --bin ledger-cli -- total
cargo run --bin ledger-cli -- report
```

## Earlier Failed Attempts

Earlier S2 attempts in this audit failed for real Merlin defects:

- Merlin tools inspected the Merlin repo instead of the extracted `rust-buggy` fixture.
- The RAG client did not consistently use the configured xcalibre-server endpoint.
- llama.cpp returned HTTP 400 when the request exceeded the available context window.
- The live loop could run too long because the in-memory planner default was 100 while serialized config treated 10 as the default.

Those defects are what the passing rerun validates.

## Cleanup

- Original `~/.merlin/config.toml` restored.
- Original `~/Library/Application Support/Merlin/providers.json` restored.
- llama.cpp router stopped.
- xcalibre-server stopped.
- Generated xcalibre work directories removed from tracked evidence to avoid committing throwaway secrets.

## Artifacts

- `rerun-live-20260526T153909Z/logs/xcodebuild-S2-local-deepseek.log`
- `rerun-live-20260526T153909Z/logs/llamacpp-router.log`
- `rerun-live-20260526T153909Z/logs/llamacpp-models-start.json`
- `rerun-live-20260526T153909Z/logs/llamacpp-models-before-s2.json`
- `rerun-live-20260526T153909Z/logs/xcalibre-build.log`
- `rerun-live-20260526T153909Z/logs/xcalibre-openapi.json`
- `rerun-live-20260526T153909Z/logs/xcalibre-server.log`
