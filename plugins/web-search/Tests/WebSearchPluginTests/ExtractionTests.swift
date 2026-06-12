import XCTest
@testable import WebSearchPlugin

final class ExtractionTests: XCTestCase {
    func testStaticHTMLExtractionProducesReadableText() async throws {
        let url = URL(string: "https://example.com/page")!
        let html = "<html><head><title>Hello</title></head><body><p>Hello world from a static HTML page with enough useful content to pass extraction.</p></body></html>"
        let extractor = URLSessionPageExtractor(httpClient: MockHTTPClient(responses: [
            url.absoluteString: HTTPResponse(url: url, statusCode: 200, headers: ["Content-Type": "text/html"], data: Data(html.utf8)),
        ]))

        let result = await extractor.extract(PageExtractionRequest(url: url.absoluteString), settings: .defaults)

        XCTAssertEqual(result.diagnostics.last?.state, .ok)
        XCTAssertEqual(result.title, "Hello")
        XCTAssertTrue(result.text.contains("Hello world"))
    }

    func testCaptchaBlocksExtraction() async throws {
        let url = URL(string: "https://example.com/captcha")!
        let extractor = URLSessionPageExtractor(httpClient: MockHTTPClient(responses: [
            url.absoluteString: HTTPResponse(url: url, statusCode: 200, headers: ["Content-Type": "text/html"], data: Data("<html>captcha required</html>".utf8)),
        ]))

        let result = await extractor.extract(PageExtractionRequest(url: url.absoluteString), settings: .defaults)

        XCTAssertEqual(result.diagnostics.first?.state, .captcha)
        XCTAssertTrue(result.text.isEmpty)
    }

    func testBotPolicyCategoriesProduceSpecificDiagnostics() async throws {
        let cases: [(String, String, ProviderDiagnosticState)] = [
            ("robots", #"<html><head><meta name="robots" content="noindex"></head><body>Useful content long enough for extraction if allowed.</body></html>"#, .botPolicyBlocked),
            ("login", "<html>Sign in to continue to this useful article content.</html>", .loginWall),
            ("javascript", "<html>Enable JavaScript to view this application content.</html>", .javascriptRequired),
            ("terms", "<html>Terms of service prohibit automated scraping robots.</html>", .providerTermsBlocked),
        ]

        for (path, html, state) in cases {
            let url = URL(string: "https://example.com/\(path)")!
            let extractor = URLSessionPageExtractor(httpClient: MockHTTPClient(responses: [
                url.absoluteString: HTTPResponse(url: url, statusCode: 200, headers: ["Content-Type": "text/html"], data: Data(html.utf8)),
            ]))

            let result = await extractor.extract(PageExtractionRequest(url: url.absoluteString), settings: .defaults)

            XCTAssertEqual(result.diagnostics.first?.state, state, path)
            XCTAssertTrue(result.text.isEmpty, path)
        }
    }

    func testUnsupportedContentProducesSpecificDiagnostic() async throws {
        let url = URL(string: "https://example.com/file.pdf")!
        let extractor = URLSessionPageExtractor(httpClient: MockHTTPClient(responses: [
            url.absoluteString: HTTPResponse(url: url, statusCode: 200, headers: ["Content-Type": "application/pdf"], data: Data("%PDF".utf8)),
        ]))

        let result = await extractor.extract(PageExtractionRequest(url: url.absoluteString), settings: .defaults)

        XCTAssertEqual(result.diagnostics.first?.state, .unsupportedContent)
        XCTAssertTrue(result.text.isEmpty)
    }

    func testBoundedFallbackUsesWebKitOnlyForRenderableFailures() async throws {
        let primary = FixedExtractor(state: .javascriptRequired, text: "", strategy: "urlsession-html")
        let fallback = FixedExtractor(state: .ok, text: "Rendered fallback text with enough content to be useful.", strategy: "webkit")
        let extractor = BoundedFallbackPageExtractor(primary: primary, fallback: fallback)

        let result = await extractor.extract(PageExtractionRequest(url: "https://example.com/app"), settings: .defaults)

        XCTAssertEqual(result.strategy, "webkit")
        XCTAssertEqual(result.diagnostics.map(\.state), [.javascriptRequired, .ok])
        XCTAssertEqual(fallback.count, 1)
    }

    func testBoundedFallbackDoesNotBypassPolicyOrDisabledSetting() async throws {
        let primary = FixedExtractor(state: .botPolicyBlocked, text: "", strategy: "urlsession-html")
        let fallback = FixedExtractor(state: .ok, text: "Rendered fallback text with enough content to be useful.", strategy: "webkit")
        let extractor = BoundedFallbackPageExtractor(primary: primary, fallback: fallback)

        let policyResult = await extractor.extract(PageExtractionRequest(url: "https://example.com/policy"), settings: .defaults)

        XCTAssertEqual(policyResult.strategy, "urlsession-html")
        XCTAssertEqual(fallback.count, 0)

        var settings = WebSearchSettings.defaults
        settings.webkitExtractionEnabled = false
        let parseFailed = BoundedFallbackPageExtractor(
            primary: FixedExtractor(state: .parseFailed, text: "", strategy: "urlsession-html"),
            fallback: fallback
        )

        let disabledResult = await parseFailed.extract(PageExtractionRequest(url: "https://example.com/parse"), settings: settings)

        XCTAssertEqual(disabledResult.strategy, "urlsession-html")
        XCTAssertEqual(fallback.count, 0)
    }

    func testAdvisoryBotPolicyCanBeIgnored() async throws {
        let url = URL(string: "https://example.com/robots")!
        let html = #"<html><head><meta name="robots" content="noarchive"></head><body><p>This page has advisory policy but useful static content long enough for extraction.</p></body></html>"#
        let extractor = URLSessionPageExtractor(httpClient: MockHTTPClient(responses: [
            url.absoluteString: HTTPResponse(url: url, statusCode: 200, headers: ["Content-Type": "text/html"], data: Data(html.utf8)),
        ]))
        var settings = WebSearchSettings.defaults
        settings.botPolicyMode = .ignoreAdvisory

        let result = await extractor.extract(PageExtractionRequest(url: url.absoluteString), settings: settings)

        XCTAssertTrue(result.diagnostics.contains { $0.message.contains("ignored") })
        XCTAssertFalse(result.text.isEmpty)
    }
}

private final class FixedExtractor: PageExtractionProvider, @unchecked Sendable {
    let id = "fixed"
    private let state: ProviderDiagnosticState
    private let text: String
    private let strategy: String
    private(set) var count = 0

    init(state: ProviderDiagnosticState, text: String, strategy: String) {
        self.state = state
        self.text = text
        self.strategy = strategy
    }

    func extract(_ request: PageExtractionRequest, settings: WebSearchSettings) async -> PageExtractionResult {
        count += 1
        return PageExtractionResult(
            requestedURL: request.url,
            finalURL: request.url,
            contentType: "text/html",
            byteCount: text.utf8.count,
            title: nil,
            text: text,
            strategy: strategy,
            truncated: false,
            diagnostics: [ProviderDiagnostic(providerID: id, state: state, message: "\(state)")],
            cached: false
        )
    }
}
