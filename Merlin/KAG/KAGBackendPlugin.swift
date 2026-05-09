//  KAGBackendPlugin.swift — protocol, NullKAGPlugin, and KAGBackendRegistry.

import Foundation

// MARK: - Protocol

/// Any conforming type can store and retrieve knowledge graph triples.
public protocol KAGBackendPlugin: Sendable {
    /// Persist the supplied triples. Implementations should be idempotent on duplicate inserts.
    func writeTriples(_ triples: [KAGTriple]) async throws
    /// BFS-traverse the graph from `anchor` up to `hops` hops, optionally filtered by domain.
    func traverse(anchor: String, hops: Int, domainId: String?) async throws -> [KAGTriple]
}

// MARK: - Null implementation

/// Default no-op plugin used until a real backend is registered.
public final class NullKAGPlugin: KAGBackendPlugin, @unchecked Sendable {
    public init() {}
    public func writeTriples(_ triples: [KAGTriple]) async throws {}
    public func traverse(anchor: String, hops: Int, domainId: String?) async throws -> [KAGTriple] {
        return []
    }
}

// MARK: - Registry

/// @MainActor singleton that holds the active KAG backend.
@MainActor
public final class KAGBackendRegistry {
    /// Process-wide singleton.
    public static let shared = KAGBackendRegistry()

    private(set) public var current: any KAGBackendPlugin

    public init() {
        current = NullKAGPlugin()
    }

    /// Replaces the active backend. Call at startup after deciding which plugin to use.
    public func register(_ plugin: any KAGBackendPlugin) {
        current = plugin
    }
}
