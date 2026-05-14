import Foundation

enum RedactedString {
    static func redacted(_ input: String) -> String {
        let patterns = [
            #"sk-[A-Za-z0-9_-]{8,}"#,
            #"pk-[A-Za-z0-9_-]{8,}"#,
            #"Bearer [A-Za-z0-9._-]+"#
        ]

        var output = input
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(output.startIndex..., in: output)
            output = regex.stringByReplacingMatches(
                in: output,
                options: [],
                range: range,
                withTemplate: "[redacted]"
            )
        }

        if output.count > 500 {
            output = String(output.prefix(500))
        }
        return output
    }
}
