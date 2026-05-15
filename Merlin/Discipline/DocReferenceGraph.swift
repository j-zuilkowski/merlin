import Foundation

/// Stub implementation — replaced by full graph in phase 251b.
actor DocReferenceGraph {
    func build(projectPath: String) async -> [DocReference] {
        _ = projectPath
        return []
    }

    func staleReferences(against changedSymbols: [String]) async -> [DocReference] {
        _ = changedSymbols
        return []
    }
}

struct DocReference: Sendable {
    let docFile: String
    let docSection: String?
    let codeSymbol: String
    let sourceFile: String?
}
