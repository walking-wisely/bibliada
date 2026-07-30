import Foundation

/// A single Bible verse, either fetched from bible-api.com or loaded from the bundled catalog.
struct Verse: Codable, Hashable, Sendable, Identifiable {
    var id: String { reference }

    /// Human-readable reference, e.g. "John 3:16".
    let reference: String
    /// Whitespace-trimmed, newlines collapsed to single spaces.
    let text: String
    /// Translation identifier, e.g. "WEB".
    let translation: String
}
