import Foundation

enum StepCriterion: Equatable, Sendable, Codable {
    case prose(String)
    case buildSucceeds
    case testsPass(scheme: String?)
    case fileExists(path: String)
    case regexMatch(pattern: String, in: RegexTarget)
    case shellExitZero(command: String)

    enum RegexTarget: String, Codable, Equatable, Sendable {
        case stdout
        case file
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
        case scheme
        case path
        case pattern
        case target
        case command
    }

    private enum Kind: String, Codable {
        case prose
        case buildSucceeds
        case testsPass
        case fileExists
        case regexMatch
        case shellExitZero
    }

    init(from decoder: Decoder) throws {
        if let prose = try? decoder.singleValueContainer().decode(String.self) {
            self = .prose(prose)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .prose:
            self = .prose(try container.decode(String.self, forKey: .value))
        case .buildSucceeds:
            self = .buildSucceeds
        case .testsPass:
            self = .testsPass(scheme: try container.decodeIfPresent(String.self, forKey: .scheme))
        case .fileExists:
            self = .fileExists(path: try container.decode(String.self, forKey: .path))
        case .regexMatch:
            self = .regexMatch(
                pattern: try container.decode(String.self, forKey: .pattern),
                in: try container.decode(RegexTarget.self, forKey: .target)
            )
        case .shellExitZero:
            self = .shellExitZero(command: try container.decode(String.self, forKey: .command))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .prose(let text):
            try container.encode(Kind.prose, forKey: .kind)
            try container.encode(text, forKey: .value)
        case .buildSucceeds:
            try container.encode(Kind.buildSucceeds, forKey: .kind)
        case .testsPass(let scheme):
            try container.encode(Kind.testsPass, forKey: .kind)
            try container.encodeIfPresent(scheme, forKey: .scheme)
        case .fileExists(let path):
            try container.encode(Kind.fileExists, forKey: .kind)
            try container.encode(path, forKey: .path)
        case .regexMatch(let pattern, let target):
            try container.encode(Kind.regexMatch, forKey: .kind)
            try container.encode(pattern, forKey: .pattern)
            try container.encode(target, forKey: .target)
        case .shellExitZero(let command):
            try container.encode(Kind.shellExitZero, forKey: .kind)
            try container.encode(command, forKey: .command)
        }
    }
}
