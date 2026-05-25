import XCTest

final class ArchitectureStatusLabelTests: XCTestCase {

    func testArchitectureDoesNotMarkV23BuiltFeaturesAsPlanned() throws {
        let text = try repoFile("spec.md")
        XCTAssertFalse(text.contains("v2.3 planned"))
        XCTAssertTrue(text.contains("## llama.cpp First-Class Local Provider [v2.3]"))
    }

    func testArchitectureMarksCAGAsBuilt() throws {
        let text = try repoFile("spec.md")
        XCTAssertTrue(text.contains("## CAG — Cache-Augmented Generation [v11]"))
    }

    func testArchitectureCAGSectionDoesNotSayNotImplemented() throws {
        let cag = try cagSection()
        XCTAssertFalse(cag.localizedCaseInsensitiveContains("not implemented"))
        XCTAssertFalse(cag.localizedCaseInsensitiveContains("planned"))
        XCTAssertFalse(cag.localizedCaseInsensitiveContains("task work is deferred"))
    }

    func testArchitectureMentionsCAGRuntimeFiles() throws {
        let cag = try cagSection()
        XCTAssertTrue(cag.contains("Merlin/CAG/CachePolicy.swift"))
        XCTAssertTrue(cag.contains("Merlin/CAG/CacheMetrics.swift"))
        XCTAssertTrue(cag.contains("CompletionRequest.cachePolicy"))
        XCTAssertTrue(cag.contains("AnthropicProvider"))
        XCTAssertTrue(cag.contains("cache_control"))
    }

    private func cagSection() throws -> String {
        let text = try repoFile("spec.md")
        let header = "## CAG — Cache-Augmented Generation"
        guard let start = text.range(of: header)?.lowerBound else {
            XCTFail("CAG section missing")
            return ""
        }
        let tail = text[start...]
        if let nextHeader = tail.range(of: "\n## ", options: [], range: tail.index(after: tail.startIndex)..<tail.endIndex)?.lowerBound {
            return String(tail[..<nextHeader])
        }
        return String(tail)
    }

    private func repoFile(_ path: String) throws -> String {
        let url = repoRootURL().appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Unit
            .deletingLastPathComponent() // MerlinTests
            .deletingLastPathComponent() // repo root
    }
}
