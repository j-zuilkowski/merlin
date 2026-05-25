import XCTest

final class SDDArtifactCutoverTests: XCTestCase {
    private var repoRoot: URL {
        var current = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while current.path != current.deletingLastPathComponent().path {
            if FileManager.default.fileExists(
                atPath: current.appendingPathComponent("project.yml").path
            ) {
                return current
            }
            current = current.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    func testRootArtifactsUseSddNamesOnly() throws {
        XCTAssertTrue(fileExists("constitution.md"), "constitution.md must be the project instruction artifact")
        XCTAssertTrue(fileExists("spec.md"), "spec.md must be the committed design/spec artifact")
        XCTAssertTrue(fileExists("tasks"), "tasks/ must be the implementation task directory")

        XCTAssertFalse(fileExists(["CLAUDE", "md"].joined(separator: ".")))
        XCTAssertFalse(fileExists(["architecture", "md"].joined(separator: ".")))
        XCTAssertFalse(fileExists("pha" + "se" + "s"))
    }

    func testCoreSymbolsUseSddNamesOnly() throws {
        XCTAssertTrue(fileExists("Merlin/Engine/ConstitutionLoader.swift"))
        XCTAssertFalse(fileExists("Merlin/Engine/" + "CLAUDE" + "MDLoader.swift"))
        XCTAssertTrue(fileExists("Merlin/Discipline/TaskScanner.swift"))
        XCTAssertFalse(fileExists("Merlin/Discipline/" + "Ph" + "ase" + "Scanner.swift"))

        let source = try concatenatedSwiftSource()
        XCTAssertFalse(source.contains("CLAUDE" + "MDLoader"))
        XCTAssertFalse(source.contains("Ph" + "ase" + "Scanner"))
    }

    private func fileExists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent(relativePath).path)
    }

    private func concatenatedSwiftSource() throws -> String {
        let roots = ["Merlin", "MerlinTests", "MerlinDisciplineCLI", "TestHelpers"]
        var result = ""
        for root in roots {
            let url = repoRoot.appendingPathComponent(root)
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let file as URL in enumerator where file.pathExtension == "swift" {
                if file.lastPathComponent == "SDDArtifactCutoverTests.swift" { continue }
                result += try String(contentsOf: file, encoding: .utf8)
                result += "\n"
            }
        }
        return result
    }
}
