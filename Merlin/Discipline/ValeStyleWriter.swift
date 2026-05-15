import Foundation

/// Writes Merlin's Vale style files to a given directory.
struct ValeStyleWriter: Sendable {

    func writeStyles(to dir: String) async throws {
        let merlinDir = URL(fileURLWithPath: dir).appendingPathComponent("Merlin")
        try FileManager.default.createDirectory(
            at: merlinDir, withIntermediateDirectories: true, attributes: nil)

        try readabilityYML.write(
            to: merlinDir.appendingPathComponent("readability.yml"),
            atomically: true, encoding: .utf8)
        try acceptTxt.write(
            to: merlinDir.appendingPathComponent("accept.txt"),
            atomically: true, encoding: .utf8)
        try passiveVoiceYML.write(
            to: merlinDir.appendingPathComponent("passive-voice.yml"),
            atomically: true, encoding: .utf8)
        try weaselYML.write(
            to: merlinDir.appendingPathComponent("weasel.yml"),
            atomically: true, encoding: .utf8)
    }

    private let readabilityYML = """
    extends: existence
    message: "Readability grade (%s) exceeds target."
    level: warning
    link: https://vale.sh/docs/topics/styles/
    tokens:
      - Flesch-Kincaid
    """

    private let acceptTxt = """
    Merlin
    DeepSeek
    API
    RAG
    tokenizer
    LLM
    LM Studio
    xcodebuild
    SwiftUI
    DocC
    """

    private let passiveVoiceYML = """
    extends: existence
    message: "Passive voice: '%s'"
    level: warning
    link: https://vale.sh/docs/topics/styles/
    tokens:
      - \\b(is|are|was|were|been|being)\\s+\\w+ed\\b
    """

    private let weaselYML = """
    extends: existence
    message: "Hedging word: '%s'"
    level: warning
    link: https://vale.sh/docs/topics/styles/
    tokens:
      - might
      - perhaps
      - possibly
      - somewhat
      - rather
    """
}
