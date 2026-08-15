import Foundation

/// A canonical verse reference — book id + chapter + verse — independent of any
/// translation's display text or language. The join key across every bundled
/// translation file (see docs/translation-json-schema.md).
struct VerseReference: Hashable, Sendable {
    let book: String
    let chapter: Int
    let verse: Int

    /// "GEN.1.1" — the form `curated-references.json` stores.
    var key: String { "\(book).\(chapter).\(verse)" }

    init(book: String, chapter: Int, verse: Int) {
        self.book = book
        self.chapter = chapter
        self.verse = verse
    }

    init?(key: String) {
        let parts = key.split(separator: ".")
        guard parts.count == 3, let chapter = Int(parts[1]), let verse = Int(parts[2]) else { return nil }
        book = String(parts[0])
        self.chapter = chapter
        self.verse = verse
    }
}

/// Loads bundled translation corpora and the curated reference pool, decoding
/// and indexing each lazily and caching the result — the same lock-protected,
/// decode-once-then-cache shape `VerseProvider.catalog` used before this.
enum TranslationCatalog {
    /// The full decoded document for a translation id, or nil if the bundled
    /// file is missing or fails to decode. Cached after first access.
    static func document(id: String) -> TranslationDocument? {
        storage.document(id: id)
    }

    /// The curated, editorially-sound reference pool — verified present in
    /// every bundled translation by scripts/generate_curated_references.py, so
    /// a lookup below never has to fall back mid-selection. Empty (not a
    /// crash) if the bundled file is missing.
    static var curatedReferences: [VerseReference] {
        storage.curatedReferences
    }

    /// A random verse from one of `enabledTranslations`, restricted to the
    /// curated reference pool, avoiding `avoidingReference` (a `Verse.reference`
    /// display string) when there's more than one candidate. Falls back to
    /// `["WEB"]` if `enabledTranslations` is empty, and to a hardcoded verse if
    /// even that — or the curated pool — is unavailable, mirroring the old
    /// `VerseProvider.bundledRandom()` contract of never returning nothing.
    static func randomVerse(enabledTranslations: [String], avoidingReference: String?) -> Verse {
        let translations = enabledTranslations.isEmpty ? ["WEB"] : enabledTranslations
        let references = curatedReferences
        guard !references.isEmpty else { return Self.hardcodedFallback }

        var attempts = 0
        var candidate = Self.pick(translations: translations, references: references)
        while candidate?.reference == avoidingReference, attempts < 10 {
            candidate = Self.pick(translations: translations, references: references)
            attempts += 1
        }
        return candidate ?? Self.hardcodedFallback
    }

    /// One specific reference resolved against one translation, or nil if that
    /// translation doesn't contain it (e.g. WEB's 4 Textus-Receptus-only gaps —
    /// see docs/translation-json-schema.md).
    static func verse(reference: VerseReference, translationID: String) -> Verse? {
        storage.verse(reference: reference, translationID: translationID)
    }

    /// Every curated verse resolved against one translation — used by the
    /// widget's timeline to build a shuffle pool of "other" verses in the same
    /// translation as the entry anchoring that timeline.
    static func curatedVerses(translationID: String) -> [Verse] {
        curatedReferences.compactMap { storage.verse(reference: $0, translationID: translationID) }
    }

    // MARK: - Private

    private static let hardcodedFallback = Verse(
        reference: "John 3:16",
        text: "For God so loved the world, that he gave his one and only Son, that whoever believes in him should not perish, but have eternal life.",
        translation: "WEB"
    )

    private static func pick(translations: [String], references: [VerseReference]) -> Verse? {
        guard let translationID = translations.randomElement(), let reference = references.randomElement() else {
            return nil
        }
        // A translation is allowed to be missing an individual reference (versification
        // gaps); retry a few times with fresh random picks before giving up on this call.
        var attempts = 0
        var result = storage.verse(reference: reference, translationID: translationID)
        while result == nil, attempts < 5, let nextReference = references.randomElement() {
            result = storage.verse(reference: nextReference, translationID: translationID)
            attempts += 1
        }
        return result
    }

    private static let storage = CatalogStorage()

    private final class CatalogStorage: @unchecked Sendable {
        private let lock = NSLock()
        private var documents: [String: TranslationDocument] = [:]
        private var verseIndexes: [String: [String: Int]] = [:] // translationID -> (VerseReference.key -> index into document.verses)
        private var bookNames: [String: [String: String]] = [:] // translationID -> (book id -> display name)
        private var loadedCuratedReferences: [VerseReference]??

        func document(id: String) -> TranslationDocument? {
            lock.lock()
            defer { lock.unlock() }
            return documentLocked(id: id)
        }

        func verse(reference: VerseReference, translationID: String) -> Verse? {
            lock.lock()
            defer { lock.unlock() }
            guard let doc = documentLocked(id: translationID) else { return nil }
            guard let index = verseIndexes[translationID]?[reference.key] else { return nil }
            let entry = doc.verses[index]
            let bookName = bookNames[translationID]?[entry.book] ?? entry.book
            return Verse(reference: "\(bookName) \(entry.chapter):\(entry.verse)", text: entry.text, translation: doc.id)
        }

        var curatedReferences: [VerseReference] {
            lock.lock()
            defer { lock.unlock() }
            if let cached = loadedCuratedReferences { return cached ?? [] }
            let loaded = Self.loadCuratedReferences()
            loadedCuratedReferences = loaded
            return loaded ?? []
        }

        /// Must be called with `lock` already held.
        private func documentLocked(id: String) -> TranslationDocument? {
            if let cached = documents[id] { return cached }
            guard let doc = Self.load(id: id) else { return nil }
            documents[id] = doc
            var index: [String: Int] = [:]
            index.reserveCapacity(doc.verses.count)
            for (i, entry) in doc.verses.enumerated() {
                index[VerseReference(book: entry.book, chapter: entry.chapter, verse: entry.verse).key] = i
            }
            verseIndexes[id] = index
            var names: [String: String] = [:]
            for book in doc.books { names[book.id] = book.name }
            bookNames[id] = names
            return doc
        }

        private static func load(id: String) -> TranslationDocument? {
            let bundle = Bundle(for: BundleToken.self)
            let filename = id.lowercased()
            guard let url = bundle.url(forResource: filename, withExtension: "json", subdirectory: "Translations")
                ?? bundle.url(forResource: filename, withExtension: "json") else {
                return nil
            }
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(TranslationDocument.self, from: data)
        }

        private static func loadCuratedReferences() -> [VerseReference]? {
            let bundle = Bundle(for: BundleToken.self)
            guard let url = bundle.url(forResource: "curated-references", withExtension: "json") else {
                return nil
            }
            guard let data = try? Data(contentsOf: url) else { return nil }
            guard let keys = try? JSONDecoder().decode([String].self, from: data) else { return nil }
            return keys.compactMap(VerseReference.init(key:))
        }
    }

    private final class BundleToken {}
}
