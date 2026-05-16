import Foundation

/// Bounds the size of a tool result before it enters the conversation context.
/// A single `git diff` / `cargo test` / large file read must never overrun the
/// provider's input window.
enum ToolOutput {

    /// Maximum characters of a tool result allowed into the model context.
    static let maxChars = 30_000

    /// Returns `text` unchanged when within `maxChars`; otherwise returns the head
    /// plus the tail of `text` with an elision marker between them. Head and tail are
    /// both kept - a `cargo test` summary lives at the end, a `git diff` header at the
    /// start.
    static func clamp(_ text: String, maxChars: Int = maxChars) -> String {
        guard text.count > maxChars else { return text }
        let headChars = maxChars * 2 / 3
        let tailChars = maxChars - headChars
        let head = String(text.prefix(headChars))
        let tail = String(text.suffix(tailChars))
        let elided = text.count - head.count - tail.count
        return head
            + "\n\n[... \(elided) characters elided - tool output truncated to "
            + "\(maxChars) chars. Re-run with a narrower command or read a specific "
            + "range to see more. ...]\n\n"
            + tail
    }
}
