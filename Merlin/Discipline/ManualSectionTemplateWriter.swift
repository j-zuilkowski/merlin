import Foundation

/// Appends a template manual section for an uncovered surface to a doc file.
struct ManualSectionTemplateWriter: Sendable {

    func write(gap: ManualCoverageGap, to docPath: String) async throws {
        let url = URL(fileURLWithPath: docPath)
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""

        if existing.contains(gap.surface) {
            return
        }

        let section = buildSection(gap: gap)
        let updated = existing + "\n" + section
        try updated.write(to: url, atomically: true, encoding: .utf8)
    }

    private func buildSection(gap: ManualCoverageGap) -> String {
        return """
        ## Manual Coverage

        <!-- covers:
             - \(gap.surface)
        -->

        > TODO: Document this \(gap.surfaceType) surface.

        """
    }
}
