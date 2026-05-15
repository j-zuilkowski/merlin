import Foundation

/// Minimal TOML parser for `ProjectAdapter` files.
/// Supports flat key-value pairs, `[table]`, and `[[array-of-tables]]`.
/// Full TOML spec not required - only the adapter subset.
enum TOMLAdapterParser {

    enum ParseError: Error, Sendable {
        case missingRequiredField(String)
        case invalidValue(String)
    }

    static func parse(_ toml: String) throws -> ProjectAdapter {
        var kv: [String: String] = [:]
        var docGrade: [String: Double] = [:]
        var whyTriggers: [WHYTriggerSpec] = []
        var coveragePatterns: [ManualCoveragePattern] = []

        var currentArrayTable: String?
        var currentRegex: String?
        var currentReason: String?
        var currentType: String?
        var currentPatternRegex: String?

        let lines = toml.components(separatedBy: .newlines)
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            if line.hasPrefix("[[") && line.hasSuffix("]]") {
                if currentArrayTable == "why_comment_triggers",
                   let r = currentRegex,
                   let reason = currentReason {
                    whyTriggers.append(WHYTriggerSpec(regex: r, reason: reason))
                    currentRegex = nil
                    currentReason = nil
                } else if currentArrayTable == "manual_coverage_patterns",
                          let t = currentType,
                          let r = currentPatternRegex {
                    coveragePatterns.append(ManualCoveragePattern(type: t, regex: r))
                    currentType = nil
                    currentPatternRegex = nil
                }
                currentArrayTable = String(line.dropFirst(2).dropLast(2))
                continue
            }

            if line.hasPrefix("[") && line.hasSuffix("]") && !line.hasPrefix("[[") {
                if currentArrayTable == "why_comment_triggers",
                   let r = currentRegex,
                   let reason = currentReason {
                    whyTriggers.append(WHYTriggerSpec(regex: r, reason: reason))
                    currentRegex = nil
                    currentReason = nil
                } else if currentArrayTable == "manual_coverage_patterns",
                          let t = currentType,
                          let r = currentPatternRegex {
                    coveragePatterns.append(ManualCoveragePattern(type: t, regex: r))
                    currentType = nil
                    currentPatternRegex = nil
                }
                currentArrayTable = String(line.dropFirst(1).dropLast(1))
                continue
            }

            guard let eqRange = line.range(of: "=") else {
                continue
            }

            let key = line[line.startIndex..<eqRange.lowerBound]
                .trimmingCharacters(in: .whitespaces)
            let rawVal = line[eqRange.upperBound...]
                .trimmingCharacters(in: .whitespaces)
            let val = rawVal.hasPrefix("\"") && rawVal.hasSuffix("\"")
                ? String(rawVal.dropFirst().dropLast())
                : String(rawVal)

            switch currentArrayTable {
            case "doc_target_grade":
                if let d = Double(val) {
                    docGrade[key] = d
                }
            case "why_comment_triggers":
                if key == "regex" {
                    currentRegex = val
                } else if key == "reason" {
                    currentReason = val
                }
            case "manual_coverage_patterns":
                if key == "type" {
                    currentType = val
                } else if key == "regex" {
                    currentPatternRegex = val
                }
            default:
                kv[key] = val
            }
        }

        if currentArrayTable == "why_comment_triggers",
           let r = currentRegex,
           let reason = currentReason {
            whyTriggers.append(WHYTriggerSpec(regex: r, reason: reason))
        } else if currentArrayTable == "manual_coverage_patterns",
                  let t = currentType,
                  let r = currentPatternRegex {
            coveragePatterns.append(ManualCoveragePattern(type: t, regex: r))
        }

        guard let language = kv["language"] else {
            throw ParseError.missingRequiredField("language")
        }
        guard let versioningFile = kv["versioning_file"] else {
            throw ParseError.missingRequiredField("versioning_file")
        }
        guard let versioningField = kv["versioning_field"] else {
            throw ParseError.missingRequiredField("versioning_field")
        }

        return ProjectAdapter(
            language: language,
            versioningFile: versioningFile,
            versioningField: versioningField,
            buildCommand: kv["build_command"] ?? "",
            testCommand: kv["test_command"] ?? "",
            buildSuccessMarker: kv["build_success_marker"] ?? "BUILD SUCCEEDED",
            buildFailureMarker: kv["build_failure_marker"] ?? "BUILD FAILED",
            releaseCommand: kv["release_command"] ?? "",
            apiDocGenerator: kv["api_doc_generator"] ?? "none",
            docTargetGrade: docGrade,
            whyCommentTriggers: whyTriggers,
            manualCoveragePatterns: coveragePatterns
        )
    }
}
