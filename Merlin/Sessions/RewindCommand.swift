import Foundation

/// Parses `/rewind` and `/rewind N` slash commands.
enum RewindCommand {
    struct ParseResult {
        let stepsBack: Int
        let valid:     Bool
    }

    /// Parses a raw slash command string.
    ///
    /// - `/rewind`   → stepsBack = 1 (go back one checkpoint)
    /// - `/rewind N` → stepsBack = N (must be ≥ 1)
    /// - anything else → valid = false
    static func parse(_ input: String) -> (stepsBack: Int, valid: Bool) {
        let parts = input.trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        guard parts.first?.lowercased() == "/rewind" else {
            return (0, false)
        }

        if parts.count == 1 {
            return (1, true)   // bare /rewind → go back 1
        }

        guard parts.count == 2,
              let n = Int(parts[1]),
              n >= 1
        else {
            return (0, false)  // non-numeric or ≤ 0 argument
        }

        return (n, true)
    }
}
