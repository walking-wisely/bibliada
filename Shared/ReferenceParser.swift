import Foundation

/// One successfully parsed reference, kept alongside the text it came from so
/// the omnibar can show a token labelled the way the user typed it.
struct ParsedReference: Hashable, Sendable {
    let source: String
    let range: VerseRange
}

/// A fragment that didn't parse, and why — surfaced inline by the omnibar and
/// listed by plain-text import rather than dropped silently.
struct ReferenceParseFailure: Hashable, Sendable {
    enum Reason: Hashable, Sendable {
        /// No book name matched the leading words.
        case unknownBook(String)
        /// The book matched but the chapter/verse numbers didn't make sense.
        case malformed
        /// Parsed cleanly but names something the canon doesn't have.
        case outOfRange
    }

    let source: String
    let reason: Reason
}

struct ReferenceParseResult: Hashable, Sendable {
    var references: [ParsedReference]
    var failures: [ReferenceParseFailure]

    var isEmpty: Bool { references.isEmpty && failures.isEmpty }
}

/// Parses human-typed scripture references into canonical `VerseRange`s.
///
/// This is the single parser behind three surfaces — the pool editor's
/// reference omnibar, pasted text, and plain-text `.txt` import — so a string
/// that works in one works in all of them. It lives in `Shared/` because the
/// widget target links the same code.
///
/// Accepted, roughly: `Ps 23`, `Psalm 23:1`, `Psalm 23:1-6`, `Rom 8:28-39`,
/// `1 Cor 13`, `1Cor13:4-7`, `PSA.23.1`, and the localized book names each
/// bundled translation carries (`Пс 23`). Fragments are separated by `;`,
/// newlines, or commas; a comma continues the previous book (`Rom 8:28, 31`).
enum ReferenceParser {
    // MARK: - Parsing

    static func parse(_ input: String) -> ReferenceParseResult {
        var result = ReferenceParseResult(references: [], failures: [])
        var lastBook: String?
        var lastChapter: Int?

        for fragment in fragments(of: input) {
            let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            switch parseFragment(trimmed, carryingBook: lastBook, chapter: lastChapter) {
            case .success(let range):
                result.references.append(ParsedReference(source: trimmed, range: range))
                lastBook = range.book
                lastChapter = range.chapter ?? lastChapter
            case .failure(let reason):
                result.failures.append(ReferenceParseFailure(source: trimmed, reason: reason))
            }
        }
        return result
    }

    /// Single-reference convenience — nil if the string doesn't parse to
    /// exactly one range.
    static func parseOne(_ input: String) -> VerseRange? {
        let result = parse(input)
        guard result.failures.isEmpty, result.references.count == 1 else { return nil }
        return result.references[0].range
    }

    // MARK: - Book matching

    /// The canonical book id a user-typed name refers to, or nil.
    ///
    /// Matches canonical ids, every bundled translation's own book names, and
    /// unambiguous prefixes of them, all case- and diacritic-insensitively with
    /// punctuation and spacing ignored (`1 Cor.`, `1cor`, `І Кор` all land on
    /// `1CO`).
    static func bookID(matching name: String) -> String? {
        let needle = normalize(name)
        guard !needle.isEmpty else { return nil }
        let index = lookup
        if let exact = index.exact[needle] { return exact }
        let prefixMatches = Set(index.exact.filter { $0.key.hasPrefix(needle) }.map(\.value))
        return prefixMatches.count == 1 ? prefixMatches.first : nil
    }

    /// Books whose names start with `prefix`, in canonical order — what the
    /// omnibar's autocomplete popover lists.
    static func completions(for prefix: String, limit: Int = 8) -> [CanonBook] {
        let needle = normalize(prefix)
        guard !needle.isEmpty else { return [] }
        let matched = Set(lookup.exact.filter { $0.key.hasPrefix(needle) }.map(\.value))
        return BibleCanon.books.filter { matched.contains($0.bookID) }.prefix(limit).map { $0 }
    }

    // MARK: - Display

    /// A range rendered the way it should appear in a rule row or a token:
    /// `Psalm 23`, `Romans 8:28–39`, `1 Corinthians 13:4`.
    static func displayString(for range: VerseRange, translationID: String) -> String {
        let bookName = BibleCanon.book(id: range.book)?.name(translationID: translationID) ?? range.book
        guard let chapter = range.chapter else { return bookName }
        guard let verses = range.verses else { return "\(bookName) \(chapter)" }
        if verses.lowerBound == verses.upperBound { return "\(bookName) \(chapter):\(verses.lowerBound)" }
        return "\(bookName) \(chapter):\(verses.lowerBound)–\(verses.upperBound)"
    }

    // MARK: - Private

    private static func fragments(of input: String) -> [String] {
        input.split(whereSeparator: { $0 == ";" || $0 == "\n" || $0 == "\r" || $0 == "," }).map(String.init)
    }

    private enum FragmentResult {
        case success(VerseRange)
        case failure(ReferenceParseFailure.Reason)
    }

    /// `carryingBook`/`carryingChapter` support comma continuation: in
    /// `Rom 8:28, 31` the second fragment is a bare verse in the same chapter,
    /// and in `Rom 8:28, 12:1` a bare chapter:verse in the same book.
    private static func parseFragment(
        _ fragment: String,
        carryingBook: String?,
        chapter carryingChapter: Int?
    ) -> FragmentResult {
        // Canonical key form ("PSA.23.1", "ROM.8.28-39") passes straight through:
        // it's what export files and internal round-trips use.
        if fragment.contains("."), let range = VerseRange(key: fragment.uppercased()),
           BibleCanon.book(id: range.book) != nil {
            return validate(range)
        }

        var (namePart, numberPart) = splitBookName(fragment)
        // A fragment that is nothing but digits ("31" in "Rom 8:28, 31") is a
        // continuation, never a book — without this "3" prefix-matches 3 John.
        if !namePart.isEmpty, namePart.allSatisfy(\.isNumber), carryingBook != nil {
            numberPart = fragment
            namePart = ""
        }

        let bookID: String
        if namePart.isEmpty {
            guard let carried = carryingBook else { return .failure(.unknownBook(fragment)) }
            bookID = carried
        } else if let matched = self.bookID(matching: namePart) {
            bookID = matched
        } else {
            return .failure(.unknownBook(namePart))
        }

        let numbers = numberPart.trimmingCharacters(in: .whitespaces)
        if numbers.isEmpty {
            return validate(VerseRange(book: bookID))
        }

        // "8:28-39" | "8:28" | "23" | (continuation) "31"
        let sides = numbers.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        if sides.count == 1 {
            guard let value = Int(sides[0].trimmingCharacters(in: .whitespaces)) else { return .failure(.malformed) }
            // A bare number after a comma continues the previous chapter as a verse;
            // otherwise it names a chapter.
            if namePart.isEmpty, let chapter = carryingChapter {
                return validate(VerseRange(book: bookID, chapter: chapter, verses: value...value))
            }
            return validate(VerseRange(book: bookID, chapter: value))
        }

        guard let chapter = Int(sides[0].trimmingCharacters(in: .whitespaces)) else { return .failure(.malformed) }
        guard let verses = parseVerseSpan(String(sides[1])) else { return .failure(.malformed) }
        return validate(VerseRange(book: bookID, chapter: chapter, verses: verses))
    }

    private static func parseVerseSpan(_ text: String) -> ClosedRange<Int>? {
        let normalized = text
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .trimmingCharacters(in: .whitespaces)
        let parts = normalized.split(separator: "-", maxSplits: 1)
        guard let lower = Int(parts.first?.trimmingCharacters(in: .whitespaces) ?? "") else { return nil }
        guard parts.count > 1 else { return lower...lower }
        guard let upper = Int(parts[1].trimmingCharacters(in: .whitespaces)), upper >= lower else { return nil }
        return lower...upper
    }

    /// Splits `"1 Cor 13:4"` into `("1 Cor", "13:4")`: the book name runs up to
    /// the last number that isn't part of a leading ordinal ("1 ", "2 ", "3 ").
    private static func splitBookName(_ fragment: String) -> (String, String) {
        let characters = Array(fragment)
        var index = 0
        // Skip a leading ordinal and any space after it.
        if let first = characters.first, first.isNumber {
            index = 1
            while index < characters.count, characters[index] == " " { index += 1 }
        }
        while index < characters.count, !characters[index].isNumber { index += 1 }
        let name = String(characters[0..<index]).trimmingCharacters(in: .whitespaces)
        let rest = String(characters[index...])
        return (name, rest)
    }

    private static func validate(_ range: VerseRange) -> FragmentResult {
        guard let book = BibleCanon.book(id: range.book) else { return .failure(.unknownBook(range.book)) }
        guard let chapter = range.chapter else { return .success(range) }
        let available = book.verseCount(chapter: chapter)
        guard available > 0 else { return .failure(.outOfRange) }
        guard let verses = range.verses else { return .success(range) }
        guard verses.lowerBound <= available else { return .failure(.outOfRange) }
        // A span running past the end of the chapter clamps rather than failing:
        // "Rom 8:28-99" plainly means "to the end".
        return .success(VerseRange(book: range.book, chapter: chapter, verses: verses.lowerBound...min(verses.upperBound, available)))
    }

    /// Lowercased, diacritic-stripped, with everything but letters and digits
    /// removed — so `"1 Cor."`, `"1cor"` and `"1 Corinthians"`'s prefix all
    /// compare equal.
    private static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }

    private struct Lookup {
        /// normalized name -> canonical book id
        var exact: [String: String] = [:]
    }

    private static let lookup: Lookup = {
        var result = Lookup()
        for book in BibleCanon.books {
            result.exact[normalize(book.bookID)] = book.bookID
            for name in book.names.values {
                result.exact[normalize(name)] = book.bookID
            }
        }
        for (alias, bookID) in aliases {
            result.exact[normalize(alias)] = bookID
        }
        return result
    }()

    /// Abbreviations that aren't prefixes of any bundled book name, so prefix
    /// matching alone can't reach them — "Jn" for John, "Jas" for James. Forms
    /// that *are* prefixes ("Gen", "Rom", "1 Cor") need no entry, and localized
    /// abbreviations are covered by prefix matching against each translation's
    /// own names.
    private static let aliases: [String: String] = [
        "dt": "DEU", "nm": "NUM", "jos": "JOS", "jdg": "JDG",
        "1sm": "1SA", "2sm": "2SA", "1kgs": "1KI", "2kgs": "2KI", "1ki": "1KI", "2ki": "2KI",
        "1chr": "1CH", "2chr": "2CH", "neh": "NEH",
        "pss": "PSA", "prv": "PRO", "qoh": "ECC", "sos": "SNG", "cant": "SNG", "song": "SNG",
        "songofsongs": "SNG", "songofsolomon": "SNG",
        "ezk": "EZK", "hos": "HOS", "obad": "OBA", "jnh": "JON", "mic": "MIC",
        "nah": "NAM", "zeph": "ZEP", "zech": "ZEC",
        "mt": "MAT", "mk": "MRK", "lk": "LUK", "jn": "JHN",
        "1jn": "1JN", "2jn": "2JN", "3jn": "3JN",
        "phlm": "PHM", "philem": "PHM", "jas": "JAS",
        // "Phil" is a prefix of both Philippians and Philemon; usage means the former.
        "phil": "PHP", "php": "PHP",
        "1pt": "1PE", "2pt": "2PE", "rv": "REV", "apoc": "REV",
    ]
}
