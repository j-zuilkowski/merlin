import Foundation

/// Structured error from an LLM provider HTTP request.
///
/// Carries the HTTP status code and response body so callers can classify
/// the failure as retriable (transient) or non-retriable (permanent) and
/// apply appropriate back-off delays.
enum ProviderError: Error, Sendable {
    /// The server responded with a non-2xx HTTP status.
    case httpError(statusCode: Int, body: String, providerID: String)
    /// A transport-level failure occurred before or during the response.
    case networkError(underlying: URLError, providerID: String)

    // MARK: - Classification

    /// True when retrying the request has a reasonable chance of succeeding.
    ///
    /// Retriable:
    ///  - `429 Too Many Requests` — rate-limited; back off and retry.
    ///  - `500…599` — transient server fault.
    ///  - Network timeouts, connection resets, and similar transport errors.
    ///
    /// Non-retriable:
    ///  - `400 Bad Request` — malformed payload; retrying is pointless.
    ///  - `401 / 403` — credential problem; a fresh request won't help.
    ///  - Any other 4xx not listed above.
    var isRetriable: Bool {
        switch self {
        case .httpError(let code, _, _):
            return code == 429 || (500...599).contains(code)
        case .networkError(let err, _):
            return [
                URLError.timedOut,
                .networkConnectionLost,
                .notConnectedToInternet,
                .cannotConnectToHost,
                .cannotFindHost,
                .badServerResponse,
            ].contains(err.code)
        }
    }

    /// True when the provider rejected the request because the prompt exceeded its context window.
    /// These errors should trigger compaction + one retry rather than surfacing to the user.
    var isContextLengthExceeded: Bool {
        guard case .httpError(let code, let body, _) = self, code == 400 else { return false }
        let lower = body.lowercased()
        return lower.contains("context_length_exceeded")
            || lower.contains("maximum context length")
            || lower.contains("input too long")
            || lower.contains("prompt is too long")
            || lower.contains("context window")
            || lower.contains("request body too large")
            || lower.contains("payload too large")
            || lower.contains("request entity too large")
            || lower.contains("body size limit exceeded")
            || lower.contains("maximum request body size")
            || lower.contains("content length exceeded")
    }

    // MARK: - Back-off

    /// Recommended delay before the next retry attempt.
    var retryDelay: TimeInterval {
        switch self {
        case .httpError(429, _, _): return 10
        case .httpError:            return 5
        case .networkError:         return 3
        }
    }

    // MARK: - Accessors

    /// The HTTP status code, or `nil` for network errors.
    var statusCode: Int? {
        guard case .httpError(let code, _, _) = self else { return nil }
        return code
    }

    /// Human-readable description suitable for log output.
    var logDescription: String {
        switch self {
        case .httpError(let code, let body, let pid):
            return "[\(pid)] HTTP \(code): \(body.prefix(200))"
        case .networkError(let err, let pid):
            return "[\(pid)] network error \(err.code.rawValue): \(err.localizedDescription)"
        }
    }
}
