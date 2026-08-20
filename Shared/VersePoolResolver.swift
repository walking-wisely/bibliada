import Foundation

/// Turns a pool's rules into the concrete list of verse references it selects.
///
/// Resolution is pure and canon-driven: it consults `BibleCanon` for chapter
/// and verse counts and never decodes a translation corpus, so it's cheap
/// enough to call whenever rules change (the editor's live verse counter does
/// exactly that). Whether a resolved reference actually *exists* in a given
/// translation is a separate question — see `missingReferences(in:)`.
enum VersePoolResolver {
    /// Every reference the rules select, in canonical order, deduplicated.
    ///
    /// Rules apply in order and later rules win: an exclusion removes anything
    /// added before it, and a later inclusion can add a verse back.
    static func resolve(rules: [PoolRule]) -> [VerseReference] {
        var selected: Set<String> = []
        for rule in rules {
            let keys = expand(rule.range).map(\.key)
            if rule.isExclusion {
                selected.subtract(keys)
            } else {
                selected.formUnion(keys)
            }
        }
        return selected.compactMap(VerseReference.init(key:)).sorted(by: canonicalOrder)
    }

    /// Verse count without materializing the reference list — what the editor's
    /// counter and the pool list's per-row count call.
    static func count(rules: [PoolRule]) -> Int {
        resolve(rules: rules).count
    }

    /// Every reference a single range covers. An empty result means the range
    /// names a book, chapter or verse span the canon doesn't have.
    static func expand(_ range: VerseRange) -> [VerseReference] {
        guard let book = BibleCanon.book(id: range.book) else { return [] }
        guard let chapter = range.chapter else {
            return (1...max(book.chapterCount, 1)).flatMap { chapter -> [VerseReference] in
                let count = book.verseCount(chapter: chapter)
                guard count > 0 else { return [] }
                return (1...count).map { VerseReference(book: book.bookID, chapter: chapter, verse: $0) }
            }
        }
        let available = book.verseCount(chapter: chapter)
        guard available > 0 else { return [] }
        let span = range.verses ?? 1...available
        let lower = max(span.lowerBound, 1)
        let upper = min(span.upperBound, available)
        guard lower <= upper else { return [] }
        return (lower...upper).map { VerseReference(book: book.bookID, chapter: chapter, verse: $0) }
    }

    /// References the pool selects that `translationID` doesn't contain.
    ///
    /// The canon is the union across bundled translations, so a pool can name a
    /// verse a particular translation omits (WEB's four Textus-Receptus-only
    /// gaps — see docs/translation-json-schema.md). Import validation reports
    /// these rather than dropping them silently; selection just skips them.
    ///
    /// Decodes the translation corpus, so this is not for hot paths.
    static func missingReferences(in translationID: String, rules: [PoolRule]) -> [VerseReference] {
        resolve(rules: rules).filter { TranslationCatalog.verse(reference: $0, translationID: translationID) == nil }
    }

    /// Book order, then chapter, then verse — the order a reader expects a
    /// rule's expansion or a search result list to be in.
    static func canonicalOrder(_ lhs: VerseReference, _ rhs: VerseReference) -> Bool {
        let lhsOrder = BibleCanon.book(id: lhs.book)?.order ?? .max
        let rhsOrder = BibleCanon.book(id: rhs.book)?.order ?? .max
        if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
        if lhs.chapter != rhs.chapter { return lhs.chapter < rhs.chapter }
        return lhs.verse < rhs.verse
    }
}
