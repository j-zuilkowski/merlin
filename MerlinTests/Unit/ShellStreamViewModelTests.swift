import XCTest
@testable import Merlin

@MainActor
final class ShellStreamViewModelTests: XCTestCase {

    func test_stdoutAndStderrLinesAppendInArrivalOrder() async throws {
        let harness = makeStreamHarness()
        let viewModel = ShellStreamViewModel(streamFactory: { _, _ in harness.stream })

        viewModel.start(command: "echo shell", cwd: "/tmp")
        harness.continuation.yield(ShellOutputLine(text: "stdout-1", source: .stdout))
        harness.continuation.yield(ShellOutputLine(text: "stderr-1", source: .stderr))
        harness.continuation.yield(ShellOutputLine(text: "stdout-2", source: .stdout))
        harness.continuation.finish()

        try await waitUntil(timeout: 1.0) { viewModel.records.count == 3 }

        XCTAssertEqual(viewModel.records.map(\.text), ["stdout-1", "stderr-1", "stdout-2"])
        XCTAssertEqual(viewModel.records.map(\.kind), [.stdout, .stderr, .stdout])
    }

    func test_stderrLinesAreMarkedAsErrorOutput() async throws {
        let harness = makeStreamHarness()
        let viewModel = ShellStreamViewModel(streamFactory: { _, _ in harness.stream })

        viewModel.start(command: "echo shell", cwd: nil)
        harness.continuation.yield(ShellOutputLine(text: "stderr-1", source: .stderr))
        harness.continuation.finish()

        try await waitUntil(timeout: 1.0) { viewModel.records.count == 1 }

        XCTAssertTrue(viewModel.records[0].isError)
        XCTAssertEqual(viewModel.records[0].kind, .stderr)
    }

    func test_completionRecordsExitStatus() async throws {
        let harness = makeStreamHarness()
        let viewModel = ShellStreamViewModel(streamFactory: { _, _ in harness.stream })

        viewModel.start(command: "echo shell", cwd: nil)
        harness.continuation.yield(ShellOutputLine(text: "stdout-1", source: .stdout))
        harness.continuation.yield(ShellOutputLine(text: "", source: .stdout, exitStatus: 17))
        harness.continuation.finish()

        try await waitUntil(timeout: 1.0) {
            viewModel.status == .finished(exitStatus: 17)
        }

        XCTAssertEqual(viewModel.exitStatus, 17)
        XCTAssertEqual(viewModel.records.last?.exitStatus, 17)
    }

    func test_thrownStreamErrorsSurfaceAsTerminalErrorState() async throws {
        let harness = makeStreamHarness()
        let viewModel = ShellStreamViewModel(streamFactory: { _, _ in harness.stream })

        viewModel.start(command: "echo shell", cwd: nil)
        harness.continuation.finish(throwing: TestError.streamFailed)

        try await waitUntil(timeout: 1.0) {
            if case .failed = viewModel.status {
                return true
            }
            return false
        }

        if case .failed(let message) = viewModel.status {
            XCTAssertFalse(message.isEmpty)
        } else {
            XCTFail("expected failed status")
        }
    }

    func test_cancelStopsConsumingFutureStreamValues() async throws {
        let harness = makeStreamHarness()
        let viewModel = ShellStreamViewModel(streamFactory: { _, _ in harness.stream })

        viewModel.start(command: "echo shell", cwd: nil)
        harness.continuation.yield(ShellOutputLine(text: "before-cancel", source: .stdout))

        try await waitUntil(timeout: 1.0) { viewModel.records.count == 1 }

        viewModel.cancel()
        harness.continuation.yield(ShellOutputLine(text: "after-cancel", source: .stdout))
        harness.continuation.finish()

        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(viewModel.records.map(\.text), ["before-cancel"])
        XCTAssertEqual(viewModel.status, .cancelled)
    }

    private func makeStreamHarness() -> StreamHarness {
        var continuation: AsyncThrowingStream<ShellOutputLine, Error>.Continuation!
        let stream = AsyncThrowingStream<ShellOutputLine, Error> { continuation = $0 }
        return StreamHarness(stream: stream, continuation: continuation)
    }

    private func waitUntil(timeout: TimeInterval, condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for condition")
    }
}

private struct StreamHarness {
    let stream: AsyncThrowingStream<ShellOutputLine, Error>
    let continuation: AsyncThrowingStream<ShellOutputLine, Error>.Continuation
}

private enum TestError: Error {
    case streamFailed
}
