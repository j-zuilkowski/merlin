import Foundation

struct Skill: Identifiable, Sendable {
    var id: String { name }
    var name: String
    var frontmatter: SkillFrontmatter
    var body: String
    var directory: URL
    var isProjectScoped: Bool

    static func load(from directory: URL, isProjectScoped: Bool) -> Skill? {
        let skillFile = directory.appendingPathComponent("SKILL.md")
        guard let raw = try? String(contentsOf: skillFile, encoding: .utf8) else { return nil }
        let (frontmatter, body) = parseFrontmatterAndBody(raw)
        let name = frontmatter.name.isEmpty ? directory.lastPathComponent : frontmatter.name
        return Skill(
            name: name,
            frontmatter: frontmatter,
            body: body,
            directory: directory,
            isProjectScoped: isProjectScoped
        )
    }

    private static func parseFrontmatterAndBody(_ raw: String) -> (SkillFrontmatter, String) {
        let lines = raw.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return (SkillFrontmatter(), raw)
        }

        var closingIndex: Int?
        if lines.count > 1 {
            for index in 1..<lines.count where lines[index].trimmingCharacters(in: .whitespaces) == "---" {
                closingIndex = index
                break
            }
        }

        guard let closingIndex else {
            return (SkillFrontmatter(), raw)
        }

        let yamlLines = Array(lines[1..<closingIndex])
        let bodyLines = Array(lines[(closingIndex + 1)...])
        let frontmatter = SkillFrontmatter.parse(yamlLines.joined(separator: "\n"))
        let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (frontmatter, body)
    }
}
