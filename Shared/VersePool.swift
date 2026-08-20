import Foundation

/// A canonical range of scripture: a whole book, a whole chapter, or a span of
/// verses within one chapter.
///
/// Ranges rather than resolved verse lists are what a pool stores — "all of
/// Psalms except Psalm 137" is two rules instead of 2,458 ids, the exported
/// form stays readable and hand-editable, and because ranges are expressed in
/// canonical `BOOK.C.V` terms (the join key every bundled translation shares)
/// a pool built in English resolves verbatim against Kulish. See
/// docs/verse-pool-customization.md.
struct VerseRange: Codable, Hashable, Sendable {
    /// Canonical book id, e.g. "ROM".
    let book: String
    /// nil = the whole book.
    let chapter: Int?
    /// nil = the whole chapter. Ignored when `chapter` is nil.
    let verses: ClosedRange<Int>?

    init(book: String, chapter: Int? = nil, verses: ClosedRange<Int>? = nil) {
        self.book = book
        self.chapter = chapter
        self.verses = chapter == nil ? nil : verses
    }

    /// A single verse.
    init(_ reference: VerseReference) {
        self.init(book: reference.book, chapter: reference.chapter, verses: reference.verse...reference.verse)
    }

    // MARK: - Wire form

    /// The compact serialized form, and the form the reference parser produces:
    /// `"PSA"` (whole book), `"PSA.23"` (whole chapter), `"ROM.8.28"` (one
    /// verse), `"ROM.8.28-39"` (a span).
    var key: String {
        guard let chapter else { return book }
        guard let verses else { return "\(book).\(chapter)" }
        if verses.lowerBound == verses.upperBound { return "\(book).\(chapter).\(verses.lowerBound)" }
        return "\(book).\(chapter).\(verses.lowerBound)-\(verses.upperBound)"
    }

    init?(key: String) {
        let parts = key.split(separator: ".", omittingEmptySubsequences: false)
        guard let bookPart = parts.first, !bookPart.isEmpty else { return nil }
        let book = String(bookPart)
        switch parts.count {
        case 1:
            self.init(book: book)
        case 2:
            guard let chapter = Int(parts[1]), chapter >= 1 else { return nil }
            self.init(book: book, chapter: chapter)
        case 3:
            guard let chapter = Int(parts[1]), chapter >= 1 else { return nil }
            let span = parts[2].split(separator: "-")
            guard let lower = Int(span.first ?? ""), lower >= 1 else { return nil }
            let upper = span.count > 1 ? Int(span[1]) : lower
            guard let upper, upper >= lower else { return nil }
            self.init(book: book, chapter: chapter, verses: lower...upper)
        default:
            return nil
        }
    }

    /// Encoded as its `key` string, not as a nested object — that is what makes
    /// an exported `.bibliadapool` file readable and editable by hand.
    init(from decoder: any Decoder) throws {
        let key = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = VerseRange(key: key) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Not a verse range: \(key)")
            )
        }
        self = parsed
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(key)
    }
}

/// One line of a pool: a range, either added to or subtracted from it.
struct PoolRule: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    var range: VerseRange
    var isExclusion: Bool

    init(id: UUID = UUID(), range: VerseRange, isExclusion: Bool = false) {
        self.id = id
        self.range = range
        self.isExclusion = isExclusion
    }

    /// `id` is identity for SwiftUI only — it is deliberately absent from the
    /// wire form, so a hand-written pool file needs nothing but ranges.
    private enum CodingKeys: String, CodingKey {
        case range, exclude
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        range = try container.decode(VerseRange.self, forKey: .range)
        isExclusion = try container.decodeIfPresent(Bool.self, forKey: .exclude) ?? false
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(range, forKey: .range)
        if isExclusion { try container.encode(true, forKey: .exclude) }
    }
}

/// A named, ordered set of rules defining which verses the app may show.
///
/// Rules apply in order, later winning over earlier: `[+PSA, -PSA.137]` is all
/// of Psalms without Psalm 137, and `[+PSA, -PSA.137, +PSA.137.1]` adds that
/// one verse back. Resolution lives in `VersePoolResolver`.
struct VersePool: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    var name: String
    var rules: [PoolRule]

    /// True for the bundled curated pool, which cannot be edited or deleted —
    /// only duplicated. See `VersePool.curated`.
    var isBuiltIn: Bool

    init(id: UUID = UUID(), name: String, rules: [PoolRule], isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.rules = rules
        self.isBuiltIn = isBuiltIn
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, rules, isBuiltIn
    }

    /// The built-in pool: the 178 editorially-chosen references the app shipped
    /// with before pools existed, and still the default for every user.
    ///
    /// Its rules are one single-verse range per curated reference, built at
    /// load time from `curated-references.json` rather than stored, so the
    /// curated list stays a data file and not a duplicated blob in defaults.
    static let curatedID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    static var curated: VersePool {
        VersePool(
            id: curatedID,
            name: "Curated",
            rules: TranslationCatalog.curatedReferences.map { PoolRule(range: VerseRange($0)) },
            isBuiltIn: true
        )
    }
}
