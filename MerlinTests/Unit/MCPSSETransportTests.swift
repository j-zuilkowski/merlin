import XCTest
@testable import Merlin

final class MCPSSETransportTests: XCTestCase {

    func test_parser_decodesSingleDataFrame() {
        var parser = MCPSSEFrameParser()
        let frames = parser.ingest("data: {\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"ok\":true}}\n\n")
        XCTAssertEqual(frames, [#"{"jsonrpc":"2.0","id":1,"result":{"ok":true}}"#])
    }

    func test_parser_joinsMultilineDataFrames() {
        var parser = MCPSSEFrameParser()
        let frames = parser.ingest(
            """
            data: {"jsonrpc":"2.0",
            data: "id":1,
            data: "result":{"ok":true}}

            """
        )
        XCTAssertEqual(frames, ["{\"jsonrpc\":\"2.0\",\n\"id\":1,\n\"result\":{\"ok\":true}}"])
    }

    func test_parser_ignoresCommentsAndHeartbeats() {
        var parser = MCPSSEFrameParser()
        let frames = parser.ingest(
            """
            : keepalive
            data: {"jsonrpc":"2.0","id":2,"result":{"ok":true}}

            """
        )
        XCTAssertEqual(frames, [#"{"jsonrpc":"2.0","id":2,"result":{"ok":true}}"#])
    }

    func test_transportClosedError_closesPendingRequestsOnEOF() async throws {
        let stream = AsyncThrowingStream<String, Error> { continuation in
            continuation.finish()
        }
        let transport = MCPSSETransport(
            endpoint: URL(string: "http://example.test/sse")!,
            eventStream: stream
        )

        do {
            _ = try await transport.call(method: "tools/list", params: [:])
            XCTFail("expected transportClosed error")
        } catch let error as MCPTransportError {
            if case .transportClosed = error {
                return
            }
            XCTFail("unexpected error: \(error)")
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }
}
