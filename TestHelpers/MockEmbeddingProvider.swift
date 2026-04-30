import Foundation
@testable import Merlin

/// Deterministic embedding provider for unit tests.
/// Returns a 4-dimensional vector derived from the first four Unicode scalar values of the
/// input text, normalised to [0, 1]. Two texts sharing a prefix will produce similar vectors,
/// which lets tests verify that cosine-similarity search ranks relevant content above noise.
struct MockEmbeddingProvider: EmbeddingProviderProtocol {
    let dimension: Int = 4

    func embed(_ text: String) async throws -> [Float] {
        var vector = [Float](repeating: 0, count: dimension)
        let scalars = Array(text.unicodeScalars.prefix(dimension))
        for (i, scalar) in scalars.enumerated() {
            vector[i] = Float(scalar.value) / 128.0
        }
        return vector
    }
}
