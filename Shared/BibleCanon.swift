import Foundation

/// One book in the canonical skeleton: its id, position, testament, per-
/// translation display names, and how many verses each of its chapters has.
struct CanonBook: Codable, Hashable, Sendable, Identifiable {
    var id: String { bookID }

    /// Canonical book id, e.g. "ROM". Matches `TranslationBook.id`.
    let bookID: String
    let order: Int
    let testament: String
    /// Translation id -> that translation's own name for this book.
    let names: [String: String]
    /// `verseCounts[i]` is the number of verses in chapter `i + 1`.
    let verseCounts: [Int]

    var chapterCount: Int { verseCounts.count }

    /// Verse count for a 1-based chapter number, or 0 if out of range.
    func verseCount(chapter: Int) -> Int {
        guard chapter >= 1, chapter <= verseCounts.count else { return 0 }
        return verseCounts[chapter - 1]
    }

    /// This book's name in `translationID`, falling back to any bundled name
    /// and finally to the raw id.
    func name(translationID: String) -> String {
        names[translationID] ?? names[BundledTranslations.defaultID] ?? names.values.sorted().first ?? bookID
    }

    private enum CodingKeys: String, CodingKey {
        case bookID = "id"
        case order, testament, names, verseCounts
    }
}

/// The canonical book/chapter/verse skeleton shared by every bundled
/// translation, loaded from `Shared/Resources/canon.json`.
///
/// This exists so anything that needs to *enumerate* scripture — the pool
/// browser's three columns, range resolution, reference validation — doesn't
/// have to decode a 5 MB corpus file to find out how many verses Psalm 119
/// has. The generated file is ~22 KB (see `scripts/generate_canon.py`).
///
/// Verse counts are the **union** across bundled translations, so a
/// versification gap in one translation (WEB's four Textus-Receptus-only
/// omissions — see docs/translation-json-schema.md) doesn't shrink the canon.
/// A reference being in the canon therefore does *not* guarantee
/// `TranslationCatalog.verse(reference:translationID:)` can resolve it in a
/// given translation; callers that care must still handle nil.
enum BibleCanon {
    /// Every book, in canonical order. Empty (not a crash) if the bundled file
    /// is missing or fails to decode.
    static var books: [CanonBook] { storage.books }

    static func book(id: String) -> CanonBook? { storage.book(id: id) }

    /// Number of chapters in a book, 0 if unknown.
    static func chapterCount(book: String) -> Int {
        storage.book(id: book)?.chapterCount ?? 0
    }

    /// Number of verses in a 1-based chapter, 0 if unknown.
    static func verseCount(book: String, chapter: Int) -> Int {
        storage.book(id: book)?.verseCount(chapter: chapter) ?? 0
    }

    /// Whether a reference exists anywhere in the canon. Translation-agnostic:
    /// see the note above on versification gaps.
    static func contains(_ reference: VerseReference) -> Bool {
        let count = verseCount(book: reference.book, chapter: reference.chapter)
        return reference.verse >= 1 && reference.verse <= count
    }

    /// Total verses in the canon — the ceiling any pool's verse count is
    /// measured against.
    static var totalVerseCount: Int { storage.totalVerseCount }

    // MARK: - Private

    private static let storage = CanonStorage()

    private final class CanonStorage: @unchecked Sendable {
        private let lock = NSLock()
        private var loaded: [CanonBook]?
        private var index: [String: CanonBook] = [:]

        var books: [CanonBook] {
            lock.lock()
            defer { lock.unlock() }
            return loadLocked()
        }

        func book(id: String) -> CanonBook? {
            lock.lock()
            defer { lock.unlock() }
            _ = loadLocked()
            return index[id]
        }

        var totalVerseCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return loadLocked().reduce(0) { $0 + $1.verseCounts.reduce(0, +) }
        }

        /// Must be called with `lock` already held.
        private func loadLocked() -> [CanonBook] {
            if let loaded { return loaded }
            let books = Self.load() ?? []
            loaded = books
            index = Dictionary(uniqueKeysWithValues: books.map { ($0.bookID, $0) })
            return books
        }

        private struct Document: Codable {
            let books: [CanonBook]
        }

        private static func load() -> [CanonBook]? {
            let bundle = Bundle(for: BundleToken.self)
            guard let url = bundle.url(forResource: "canon", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let document = try? JSONDecoder().decode(Document.self, from: data) else {
                return nil
            }
            return document.books.sorted { $0.order < $1.order }
        }
    }

    private final class BundleToken {}
}
