import Foundation

/// Reads a telemetry JSONL file written via `TelemetryEmitter.resetForTesting(path:)`
/// and returns the decoded event objects. Returns `[]` when the file is missing or
/// empty. Pair with `await TelemetryEmitter.shared.flushForTesting()` before calling.
func readTelemetryEvents(fromFile path: String) -> [[String: Any]] {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let content = String(data: data, encoding: .utf8) else {
        return []
    }
    return content
        .split(separator: "\n", omittingEmptySubsequences: true)
        .compactMap { line in
            try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        }
}
