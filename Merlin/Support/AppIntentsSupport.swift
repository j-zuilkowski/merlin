import AppIntents

struct MerlinMetadataIntent: AppIntent {
    static let title: LocalizedStringResource = "Merlin Metadata"

    func perform() async throws -> some IntentResult {
        .result()
    }
}
