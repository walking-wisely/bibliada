import Foundation

/// Picks a random verse from the enabled bundled translations, restricted to
/// the curated reference pool (see `TranslationCatalog`). Fully offline — no
/// network, no live fetch.
///
/// This used to fetch from bible-api.com on every refresh, re-pulling text
/// that was already sitting in the bundled catalog. That's gone: WEB, KJV and
/// Kulish are all public domain, so there's no drift in the underlying text to
/// "track" with a live re-fetch, and a live call bought nothing but a network
/// dependency, a third-party ToS to stay compliant with, and an outage path to
/// handle. See docs/translation-json-schema.md and docs/verse-source.md for
/// the full reasoning.
actor VerseProvider {
    static let shared = VerseProvider()

    /// Picks a random verse from `enabledTranslations`, avoiding the reference
    /// currently in `VerseCache` when possible, and writes the result back to
    /// the cache. Never throws — `TranslationCatalog.randomVerse` always
    /// returns something, worst case a hardcoded fallback verse.
    func nextVerse(enabledTranslations: [String]) async -> Verse {
        let avoiding = VerseCache.load()?.verse.reference
        let result = TranslationCatalog.randomVerse(enabledTranslations: enabledTranslations, avoidingReference: avoiding)
        VerseCache.save(result)
        return result
    }

    /// Synchronous, offline, cheap. Used for widget placeholders/previews and
    /// as the app's initial verse before settings are known.
    static func bundledRandom(enabledTranslations: [String] = ["WEB"]) -> Verse {
        TranslationCatalog.randomVerse(enabledTranslations: enabledTranslations, avoidingReference: nil)
    }

    /// Every curated verse in one translation, for the widget timeline's
    /// shuffle pool of "other" verses in the same translation as the entry
    /// anchoring that timeline. Mirrors the old `catalog` static var, now
    /// translation-scoped rather than WEB-only.
    static func curatedVerses(translationID: String) -> [Verse] {
        TranslationCatalog.curatedVerses(translationID: translationID)
    }
}
