import Foundation

/// Everything that can go wrong turning bytes into a `PoolDocument`, kept
/// specific rather than a single "couldn't import" case — the point of a
/// validation-first import is to tell a user hand-editing a `.bibliadapool`
/// file *what* is wrong, not just that something is.
///
/// Deliberately carries no message text: this type lives in `Shared/` (so the
/// widget can compile it too), and message text is presentation, which
/// belongs with `PoolIOLoc` in `App/` where it's actually shown.
enum PoolDocumentError: Error, Hashable, Sendable {
    /// Not JSON, or not a JSON object — a plain-text file handed to the JSON
    /// path by mistake, most likely.
    case notAnObject
    /// `"name"` absent or empty.
    case missingName
    /// `"rules"` absent.
    case missingRules
    /// `"rules"` present but empty — nothing to import.
    case noRules
    /// A `"range"` string inside `rules` that isn't a valid `BOOK.C.V` key,
    /// carried along so the message can name it (`"PSA.999" isn't a valid
    /// range`) instead of pointing at "some rule, somewhere".
    case invalidRange(String)
}

/// The `.bibliadapool` file format: `{name, createdWith, rules}`, matching
/// docs/verse-pool-customization.md exactly.
///
/// This type is the envelope only — `PoolRule`'s own `Codable` conformance
/// (see `Shared/VersePool.swift`) is what keeps a rule a single `"range"`
/// string plus an optional `"exclude"` flag, which is what makes an exported
/// pool readable and hand-editable. Nothing here may wrap that any further.
///
/// Decoding is forgiving of the ways a hand edit typically breaks a JSON file
/// — an unknown extra key (ignored, as any keyed `Codable` container already
/// does), a missing `createdWith` (this app never reads it back, only shows
/// it) — and specific about what it refuses: no name, no rules array, an
/// empty rules array, or a range string the parser can't make sense of. See
/// `PoolDocumentError`.
struct PoolDocument: Hashable, Sendable {
    var name: String
    /// Free text, shown but never parsed — "Bibliada 1.2" today, but a file
    /// edited by hand might say anything or omit it entirely.
    var createdWith: String?
    var rules: [PoolRule]

    init(name: String, rules: [PoolRule], createdWith: String? = PoolDocument.currentCreatedWith) {
        self.name = name
        self.rules = rules
        self.createdWith = createdWith
    }

    /// What this build stamps into a fresh export. Not read back on import —
    /// only ever written, so a file that has dropped the field (or was
    /// produced by some future or past version) still imports cleanly.
    static var currentCreatedWith: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Bibliada \(version)"
    }

    // MARK: - Pool <-> document

    init(pool: VersePool) {
        self.init(name: pool.name, rules: pool.rules)
    }

    /// A fresh, non-built-in pool under a new id — importing never resurrects
    /// `VersePool.curatedID` or any other specific id from the file, since a
    /// hand-edited or resent file colliding with an existing pool's id would
    /// silently overwrite it.
    func makePool() -> VersePool {
        VersePool(name: name, rules: rules)
    }
}

// MARK: - Wire form

extension PoolDocument: Codable {
    private enum CodingKeys: String, CodingKey {
        case name, createdWith, rules
    }

    init(from decoder: any Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            throw PoolDocumentError.notAnObject
        }
        guard let name = try? container.decode(String.self, forKey: .name), !name.isEmpty else {
            throw PoolDocumentError.missingName
        }
        self.name = name
        createdWith = try? container.decodeIfPresent(String.self, forKey: .createdWith)

        guard container.contains(.rules) else {
            throw PoolDocumentError.missingRules
        }
        do {
            rules = try container.decode([PoolRule].self, forKey: .rules)
        } catch let DecodingError.dataCorrupted(context) {
            // VerseRange's own decoder throws exactly this shape when a
            // "range" string doesn't parse — see VerseRange.init(from:). Its
            // debugDescription already names the offending key, which is the
            // only part worth keeping.
            let key = context.debugDescription
                .replacingOccurrences(of: "Not a verse range: ", with: "")
            throw PoolDocumentError.invalidRange(key)
        }
        guard !rules.isEmpty else {
            throw PoolDocumentError.noRules
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(createdWith, forKey: .createdWith)
        try container.encode(rules, forKey: .rules)
    }

    // MARK: - Convenience

    static func decode(from data: Data) throws -> PoolDocument {
        do {
            return try JSONDecoder().decode(PoolDocument.self, from: data)
        } catch let error as PoolDocumentError {
            throw error
        } catch is DecodingError {
            throw PoolDocumentError.notAnObject
        }
        // Any other error (e.g. data isn't UTF-8 at all) propagates as-is.
    }

    /// Pretty-printed and key-ordered `name, createdWith, rules` — matching
    /// the design doc's sample byte for byte for a freshly created document —
    /// because a format whose whole purpose is being hand-edited should also
    /// be pleasant to read.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

// MARK: - Validation report

/// What import validation reports: how many verses the pool actually
/// resolves to, and which of those the target translation doesn't contain.
///
/// Resolution and "is it in this translation" are different questions —
/// `VersePoolResolver.missingReferences` decodes the translation corpus,
/// which `resolve`/`count` deliberately don't need to. WEB has a handful of
/// Textus-Receptus-only gaps (docs/translation-json-schema.md); an import is
/// exactly where a user should learn about them, not have them silently
/// dropped from what "12 verses" claims to mean.
struct PoolValidationReport: Hashable, Sendable {
    let translationID: String
    let verseCount: Int
    let missingInTranslation: [VerseReference]

    /// The guardrail from docs/verse-pool-customization.md: an import that
    /// resolves to nothing must be refused, never saved as an empty pool.
    var resolvesToNothing: Bool { verseCount == 0 }

    static func validate(rules: [PoolRule], translationID: String) -> PoolValidationReport {
        PoolValidationReport(
            translationID: translationID,
            verseCount: VersePoolResolver.count(rules: rules),
            missingInTranslation: VersePoolResolver.missingReferences(in: translationID, rules: rules)
        )
    }
}
