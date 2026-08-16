import Foundation

/// Offline full-text search over one bundled translation's corpus — the pool
/// editor's third discovery surface alongside the reference omnibar and the
/// book/chapter/verse browser. See docs/verse-pool-customization.md.
///
/// An `actor` rather than a plain enum: scanning 31,098 verses per keystroke
/// is cheap once, but a naive per-call `.folding()` over the whole corpus
/// adds up if it ran on the caller's thread, so this hops off the main actor
/// and caches the normalized corpus it built last time.
actor VerseSearch {
    static let shared = VerseSearch()

    /// One match: the reference plus the untouched display text (never the
    /// normalized form — that's only for comparison).
    struct Hit: Hashable, Sendable {
        let reference: VerseReference
        let text: String
    }

    /// Searches `translationID`'s bundled corpus for `query`, case- and
    /// diacritic-insensitively (`"fear"` matches `"Fear"`; `"Пс"` matches
    /// `"пс"` regardless of stress marks), returning matches in the same
    /// book/chapter/verse order the browser and rule table use.
    ///
    /// `limit` caps the scan's *results*, not the corpus it walks — a query
    /// like "the" would otherwise return thousands of hits nobody scrolls to.
    func search(_ query: String, translationID: String, limit: Int = 500) -> [Hit] {
        let needle = Self.normalize(query)
        guard !needle.isEmpty, let document = TranslationCatalog.document(id: translationID) else { return [] }
        let normalizedTexts = normalizedTexts(for: translationID, document: document)

        var hits: [Hit] = []
        for (index, entry) in document.verses.enumerated() {
            guard normalizedTexts[index].contains(needle) else { continue }
            hits.append(Hit(
                reference: VerseReference(book: entry.book, chapter: entry.chapter, verse: entry.verse),
                text: entry.text
            ))
            if hits.count >= limit { break }
        }
        return hits.sorted { VersePoolResolver.canonicalOrder($0.reference, $1.reference) }
    }

    // MARK: - Private

    /// translationID -> that translation's verses, normalized once and reused
    /// across every keystroke rather than re-folded on each call — the actual
    /// cost this exists to avoid, since `TranslationCatalog.document` already
    /// caches the decode.
    private var normalizedCache: [String: [String]] = [:]

    private func normalizedTexts(for translationID: String, document: TranslationDocument) -> [String] {
        if let cached = normalizedCache[translationID] { return cached }
        let normalized = document.verses.map { Self.normalize($0.text) }
        normalizedCache[translationID] = normalized
        return normalized
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }
}
