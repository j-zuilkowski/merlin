//  KAGTriple.swift — typed entity-relationship triple for the knowledge graph.

import Foundation

/// Discriminates the provenance of a KAG triple.
public enum KAGTripleSource: String, Sendable, Codable, Equatable {
    case session = "session"
    case book    = "book"
}

/// A single entity-relationship triple in the knowledge graph.
public struct KAGTriple: Sendable, Equatable, Codable {
    public let subject:    String
    public let predicate:  String
    public let object:     String
    public let domainId:   String
    public let source:     KAGTripleSource
    public let confidence: Double

    public init(subject: String, predicate: String, object: String,
                domainId: String, source: KAGTripleSource, confidence: Double) {
        self.subject    = subject
        self.predicate  = predicate
        self.object     = object
        self.domainId   = domainId
        self.source     = source
        self.confidence = confidence
    }
}
