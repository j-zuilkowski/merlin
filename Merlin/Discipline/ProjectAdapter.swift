import Foundation

// MARK: - WHYTriggerSpec

/// A single trigger pattern that demands a nearby explanatory comment.
struct WHYTriggerSpec: Sendable, Codable, Equatable {
    let regex: String
    let reason: String
}

// MARK: - ManualCoveragePattern

/// A regex that identifies user-facing surfaces requiring manual doc coverage.
struct ManualCoveragePattern: Sendable, Codable, Equatable {
    let type: String
    let regex: String
}

// MARK: - ProjectAdapter

/// Per-language/per-toolchain configuration consumed by every v2.2 discipline component.
struct ProjectAdapter: Sendable, Codable, Equatable {
    let language: String
    let versioningFile: String
    let versioningField: String
    let buildCommand: String
    let testCommand: String
    let buildSuccessMarker: String
    let buildFailureMarker: String
    let releaseCommand: String
    let apiDocGenerator: String
    let docTargetGrade: [String: Double]
    let whyCommentTriggers: [WHYTriggerSpec]
    let manualCoveragePatterns: [ManualCoveragePattern]

    // MARK: - Stub factory (for tests and seeds)

    static func makeStub(
        language: String,
        buildCommand: String = "build"
    ) -> ProjectAdapter {
        ProjectAdapter(
            language: language,
            versioningFile: "version.txt",
            versioningField: "version",
            buildCommand: buildCommand,
            testCommand: "test",
            buildSuccessMarker: "OK",
            buildFailureMarker: "FAILED",
            releaseCommand: "release",
            apiDocGenerator: "none",
            docTargetGrade: [:],
            whyCommentTriggers: [],
            manualCoveragePatterns: []
        )
    }
}
