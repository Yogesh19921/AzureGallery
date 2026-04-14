import Foundation
import NaturalLanguage

/// Uses Apple's on-device NLEmbedding to expand a natural language search query
/// into matching Vision scene labels. This enables queries like "beach sunset"
/// to match labels like "outdoor", "ocean", "sky" via semantic similarity.
enum SemanticSearchService {
    private static let embedding = NLEmbedding.wordEmbedding(for: .english)

    /// Known Vision scene classification labels that our classifier produces.
    /// Subset of the full VNClassifyImageRequest label set.
    private static let knownLabels = [
        "outdoor", "indoor", "landscape", "sky", "ocean", "beach", "mountain",
        "forest", "garden", "park", "street", "city", "building", "house",
        "food", "drink", "people", "crowd", "selfie", "portrait",
        "animal", "dog", "cat", "bird", "car", "vehicle", "night", "sunset",
        "sunrise", "snow", "rain", "flower", "tree", "water", "lake", "river",
        "sport", "celebration", "wedding", "baby", "child", "family",
        "screenshot", "document", "text", "sign", "art", "painting",
    ]

    /// Expand a free-text query into matching scene label keywords.
    /// Returns the top N labels semantically closest to the query words.
    static func expandQuery(_ query: String, topN: Int = 5) -> [String] {
        guard let emb = embedding else { return [query.lowercased()] }

        let queryWords = query.lowercased()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        var scored: [(label: String, score: Double)] = []
        for label in knownLabels {
            var bestScore: Double = 0
            for word in queryWords {
                let dist = emb.distance(between: word, and: label)
                // NLEmbedding.distance returns cosine distance (0 = identical, 2 = opposite)
                // Returns NaN if either word is unknown — skip in that case
                if !dist.isNaN {
                    let similarity = 1.0 - dist / 2.0
                    bestScore = max(bestScore, similarity)
                }
            }
            // Also check exact substring match — always high score
            if label.contains(query.lowercased()) || query.lowercased().contains(label) {
                bestScore = max(bestScore, 0.95)
            }
            if bestScore > 0.4 {
                scored.append((label, bestScore))
            }
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(topN)
            .map(\.label)
    }
}
