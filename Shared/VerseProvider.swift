import Foundation

/// Picks the next verse from the user's active pool (see `VersePoolStore`),
/// using a shuffle bag rather than plain randomness so a small pool doesn't
/// repeat itself. Fully offline — no network, no live fetch.
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

    /// Picks the next verse from the active pool, translated into one of
    /// `enabledTranslations`, and writes the result back to the cache. Never
    /// throws and never surfaces an empty pool — see the fallback chain in
    /// `pick(pool:translations:avoidingReference:)`.
    ///
    /// Takes `enabledTranslations` (rather than reading
    /// `SettingsStore.shared.settings.translationID` itself) to keep this
    /// call's existing shape for its callers (`AppState`, the widget
    /// timeline provider); the active *pool*, which those callers have no
    /// reason to know about, is looked up here instead.
    func nextVerse(enabledTranslations: [String]) async -> Verse {
        let avoiding = VerseCache.load()?.verse.reference
        let pool = await MainActor.run { VersePoolStore.shared.activePool(settings: SettingsStore.shared.settings) }
        let result = Self.pick(pool: pool, translations: enabledTranslations, avoidingReference: avoiding)
        VerseCache.save(result)
        return result
    }

    /// Synchronous, offline, cheap — restricted to the curated pool rather
    /// than the user's active one, since the two call sites that need this
    /// (a widget's `placeholder(in:)`, the app's very first verse before
    /// `AppState` has read anything) run before pool/settings state is known
    /// to be safe to touch, and a placeholder's exact content doesn't matter.
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

    // MARK: - Private

    /// Draws one reference from `pool` via `ShuffleBag` and resolves it
    /// against a random translation from `translations`. Retries a handful of
    /// times on a translation gap (WEB's Textus-Receptus-only omissions —
    /// see docs/translation-json-schema.md) before giving up and falling back
    /// to the old curated-pool random pick, which preserves this actor's
    /// long-standing contract of never returning nothing.
    private static func pick(pool: VersePool, translations: [String], avoidingReference: String?) -> Verse {
        let translations = translations.isEmpty ? ["WEB"] : translations
        let resolved = VersePoolResolver.resolve(rules: pool.rules)
        guard !resolved.isEmpty else {
            return TranslationCatalog.randomVerse(enabledTranslations: translations, avoidingReference: avoidingReference)
        }

        var attempts = 0
        while attempts < 6 {
            guard let translationID = translations.randomElement(),
                  let reference = ShuffleBag.draw(pool: pool, resolved: resolved) else { break }
            if let verse = TranslationCatalog.verse(reference: reference, translationID: translationID) {
                return verse
            }
            attempts += 1
        }
        return TranslationCatalog.randomVerse(enabledTranslations: translations, avoidingReference: avoidingReference)
    }
}
