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
            || lower.contains("exceed_context_size_error")
            || lower.contains("maximum context length")
            || lower.contains("exceeds the available context size")
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

    /// The context-window size (tokens) the provider reported in a context-overflow
    /// 400 body, e.g. the 8192 in "maximum context length is 8192 tokens".
    var observedContextLimit: Int? {
        guard isContextLengthExceeded,
              case .httpError(_, let body, _) = self
        else {
            return nil
        }

        let lower = body.lowercased()
        if let structuredLimit = ProviderError.structuredContextLimit(in: body) {
            return structuredLimit
        }
        if let phraseLimit = ProviderError.contextLimitFromPhrases(in: lower) {
            return phraseLimit
        }
        guard let regex = try? NSRegularExpression(pattern: #"[0-9][0-9,]*"#) else {
            return nil
        }
        let fullRange = NSRange(lower.startIndex..<lower.endIndex, in: lower)
        let matches = regex.matches(in: lower, range: fullRange)
        let candidates = matches.compactMap { match -> Int? in
            guard let range = Range(match.range, in: lower) else { return nil }
            let raw = lower[range].replacingOccurrences(of: ",", with: "")
            guard let value = Int(raw),
                  (512...10_000_000).contains(value)
            else {
                return nil
            }

            let prefixDistance = lower.distance(from: lower.startIndex, to: range.lowerBound)
            let suffixDistance = lower.distance(from: range.upperBound, to: lower.endIndex)
            let start = lower.index(range.lowerBound, offsetBy: -min(prefixDistance, 80))
            let end = lower.index(range.upperBound, offsetBy: min(suffixDistance, 80))
            let context = lower[start..<end]

            guard context.contains("context length")
                    || context.contains("context window")
                    || context.contains("maximum context")
                    || context.contains("context_length")
                    || context.contains("token")
            else {
                return nil
            }
            return value
        }

        return candidates.max()
    }

    private static func structuredContextLimit(in body: String) -> Int? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data)
        else {
            return nil
        }

        let preferredKeys = [
            "n_ctx",
            "context_size",
            "context_window",
            "context_length",
            "max_context",
            "max_context_length",
            "maximum_context_length",
        ]
        for key in preferredKeys {
            if let value = firstNumericValue(forKey: key, in: json) {
                return value
            }
        }
        return nil
    }

    private static func firstNumericValue(forKey target: String, in value: Any) -> Int? {
        if let dictionary = value as? [String: Any] {
            for (key, candidate) in dictionary where key.lowercased() == target {
                if let intValue = candidate as? Int {
                    return intValue
                }
                if let number = candidate as? NSNumber {
                    return number.intValue
                }
                if let string = candidate as? String,
                   let intValue = Int(string.replacingOccurrences(of: ",", with: "")) {
                    return intValue
                }
            }
            for candidate in dictionary.values {
                if let match = firstNumericValue(forKey: target, in: candidate) {
                    return match
                }
            }
        } else if let array = value as? [Any] {
            for candidate in array {
                if let match = firstNumericValue(forKey: target, in: candidate) {
                    return match
                }
            }
        }
        return nil
    }

    private static func contextLimitFromPhrases(in lower: String) -> Int? {
        let patterns = [
            #"available context size[^0-9]{0,40}([0-9][0-9,]*)"#,
            #"context (?:window|size|length)[^0-9]{0,40}([0-9][0-9,]*)"#,
            #"maximum context[^0-9]{0,40}([0-9][0-9,]*)"#,
            #"max(?:imum)? is[^0-9]{0,40}([0-9][0-9,]*)"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
            guard let match = regex.firstMatch(in: lower, range: range),
                  match.numberOfRanges > 1,
                  let capture = Range(match.range(at: 1), in: lower)
            else {
                continue
            }
            let raw = lower[capture].replacingOccurrences(of: ",", with: "")
            if let value = Int(raw), (512...10_000_000).contains(value) {
                return value
            }
        }
        return nil
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
