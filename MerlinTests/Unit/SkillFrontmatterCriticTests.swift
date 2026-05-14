import XCTest
@testable import Merlin

@MainActor
final class SkillFrontmatterCriticTests: XCTestCase {

    private var telemetryPath: String!

    override func setUp() async throws {
        try await super.setUp()
        telemetryPath = "/tmp/merlin-skill-frontmatter-critic-\(UUID().uuidString).jsonl"
        await TelemetryEmitter.shared.resetForTesting(path: telemetryPath)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: telemetryPath)
        try await super.tearDown()
    }

    func testParseCriticRequired() {
        let skill = SkillFrontmatter.parse("""
        ---
        name: review
        critic: required
        ---
        Review the change.
        """)

        XCTAssertEqual(skill.critic, .required)
    }

    func testParseCriticSkip() {
        let skill = SkillFrontmatter.parse("""
        ---
        name: review
        critic: skip
        ---
        Review the change.
        """)

        XCTAssertEqual(skill.critic, .skip)
    }

    func testParseCriticOptional() {
        let skill = SkillFrontmatter.parse("""
        ---
        name: review
        critic: optional
        ---
        Review the change.
        """)

        XCTAssertEqual(skill.critic, .optional)
    }

    func testCriticAbsentRemainsNil() {
        let skill = SkillFrontmatter.parse("""
        ---
        name: review
        ---
        Review the change.
        """)

        XCTAssertNil(skill.critic)
    }

    func testInvalidCriticValueEmitsWarningAndStoresNil() async throws {
        let skill = SkillFrontmatter.parse("""
        ---
        name: review
        critic: maybe
        ---
        Review the change.
        """)

        XCTAssertNil(skill.critic)

        let events = try await capturedEvents()
        let warnings = events.filter { $0["event"] as? String == "skill.frontmatter.warning" }
        XCTAssertFalse(warnings.isEmpty, "Expected skill.frontmatter.warning telemetry")

        let data = warnings[0]["data"] as? [String: Any]
        XCTAssertEqual(data?["skill_id"] as? String, "review")
        XCTAssertEqual(data?["key"] as? String, "critic")
        XCTAssertEqual(data?["value"] as? String, "maybe")
    }

    private func capturedEvents() async throws -> [[String: Any]] {
        await TelemetryEmitter.shared.flushForTesting()
        guard FileManager.default.fileExists(atPath: telemetryPath),
              let content = try? String(contentsOfFile: telemetryPath, encoding: .utf8) else {
            return []
        }
        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            }
    }
}
