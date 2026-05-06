import XCTest
@testable import Merlin

final class ProviderRetryPolicyTests: XCTestCase {

    // MARK: - isRetriable

    func test_httpError_429_isRetriable() {
        XCTAssertTrue(ProviderError.httpError(statusCode: 429, body: "", providerID: "p").isRetriable)
    }

    func test_httpError_500_isRetriable() {
        XCTAssertTrue(ProviderError.httpError(statusCode: 500, body: "", providerID: "p").isRetriable)
    }

    func test_httpError_502_isRetriable() {
        XCTAssertTrue(ProviderError.httpError(statusCode: 502, body: "", providerID: "p").isRetriable)
    }

    func test_httpError_503_isRetriable() {
        XCTAssertTrue(ProviderError.httpError(statusCode: 503, body: "", providerID: "p").isRetriable)
    }

    func test_httpError_504_isRetriable() {
        XCTAssertTrue(ProviderError.httpError(statusCode: 504, body: "", providerID: "p").isRetriable)
    }

    func test_httpError_401_notRetriable() {
        XCTAssertFalse(ProviderError.httpError(statusCode: 401, body: "", providerID: "p").isRetriable)
    }

    func test_httpError_403_notRetriable() {
        XCTAssertFalse(ProviderError.httpError(statusCode: 403, body: "", providerID: "p").isRetriable)
    }

    func test_httpError_400_notRetriable() {
        XCTAssertFalse(ProviderError.httpError(statusCode: 400, body: "", providerID: "p").isRetriable)
    }

    func test_networkError_timeout_isRetriable() {
        XCTAssertTrue(ProviderError.networkError(underlying: URLError(.timedOut), providerID: "p").isRetriable)
    }

    func test_networkError_connectionLost_isRetriable() {
        XCTAssertTrue(ProviderError.networkError(underlying: URLError(.networkConnectionLost), providerID: "p").isRetriable)
    }

    func test_networkError_notConnected_isRetriable() {
        XCTAssertTrue(ProviderError.networkError(underlying: URLError(.notConnectedToInternet), providerID: "p").isRetriable)
    }

    // MARK: - retryDelay

    func test_retryDelay_429_is10s() {
        XCTAssertEqual(ProviderError.httpError(statusCode: 429, body: "", providerID: "p").retryDelay, 10)
    }

    func test_retryDelay_500_is5s() {
        XCTAssertEqual(ProviderError.httpError(statusCode: 500, body: "", providerID: "p").retryDelay, 5)
    }

    func test_retryDelay_networkError_is3s() {
        XCTAssertEqual(ProviderError.networkError(underlying: URLError(.timedOut), providerID: "p").retryDelay, 3)
    }

    // MARK: - statusCode

    func test_statusCode_httpError() {
        XCTAssertEqual(ProviderError.httpError(statusCode: 503, body: "", providerID: "p").statusCode, 503)
    }

    func test_statusCode_networkError_isNil() {
        XCTAssertNil(ProviderError.networkError(underlying: URLError(.timedOut), providerID: "p").statusCode)
    }
}
