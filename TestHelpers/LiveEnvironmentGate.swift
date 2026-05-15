import Foundation
import XCTest

/// True only when the process opted into live-environment tests via RUN_LIVE_TESTS=1.
/// Engine-driven tests need a reachable LLM endpoint and favourable timing - absent on
/// GitHub CI runners and headless sandboxes - so they are gated behind this opt-in.
func isLiveEnvironment() -> Bool {
    ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] == "1"
}

/// Skips the calling test unless running in a live environment. Call as the first
/// statement of an engine-driven test method.
func skipUnlessLiveEnvironment(
    _ reason: String = "requires a live LLM environment"
) throws {
    try XCTSkipUnless(
        isLiveEnvironment(),
        "Skipped - \(reason). Set RUN_LIVE_TESTS=1 to run.")
}
