import Foundation

/// One book entry inside a bundled translation file — this translation's own
/// display name for a canonical book id. See docs/translation-json-schema.md.
struct TranslationBook: Codable, Sendable, Hashable {
    let id: String
    let name: String
    let order: Int
    let testament: String
}

/// One verse entry inside a bundled translation file.
struct TranslationVerseEntry: Codable, Sendable, Hashable {
    let book: String
    let chapter: Int
    let verse: Int
    let text: String
}

/// The full decoded contents of one `Shared/Resources/Translations/*.json` file.
struct TranslationDocument: Codable, Sendable {
    let id: String
    let language: String
    let license: String
    let source: String
    let books: [TranslationBook]
    let verses: [TranslationVerseEntry]
}

/// Lightweight, hardcoded metadata for every bundled translation — enough to
/// populate a picker without decoding a multi-megabyte corpus file just to list
/// what's available. Keep this in sync with `Translations/*.json` whenever a
/// translation is added or removed.
struct TranslationMeta: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let language: String
    let languageName: String
}

enum BundledTranslations {
    static let all: [TranslationMeta] = [
        TranslationMeta(id: "WEB", displayName: "World English Bible", language: "en", languageName: "English"),
        TranslationMeta(id: "KJV", displayName: "King James Version", language: "en", languageName: "English"),
        TranslationMeta(id: "KULISH", displayName: "Kulish (1903)", language: "uk", languageName: "Ukrainian"),
    ]

    /// The translation used until the user picks one — the first bundled entry.
    static let defaultID: String = all.first?.id ?? "WEB"

    static func meta(id: String) -> TranslationMeta? {
        all.first { $0.id == id }
    }

    /// The first bundled translation in a given language (an ISO code like
    /// "en"/"uk"), if any — used to suggest a matching translation when the
    /// interface language changes.
    static func firstMeta(languageCode: String) -> TranslationMeta? {
        all.first { $0.language == languageCode }
    }
}
