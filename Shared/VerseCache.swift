import Foundation

/// A verse plus the time it was fetched/selected, persisted so the widget can
/// render instantly without a network round trip.
struct CachedVerse: Codable, Sendable {
    let verse: Verse
    let fetchedAt: Date
}

/// Stores the last-shown verse in the shared App Group container (falling back
/// to `UserDefaults.standard` when the App Group is unavailable), so both the
/// app and the widget extension can read the same "current verse".
enum VerseCache {
    private static let key = "cachedVerse"
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppGroup.suiteName) ?? .standard
    }

    static func load() -> CachedVerse? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CachedVerse.self, from: data)
    }

    static func save(_ verse: Verse) {
        let cached = CachedVerse(verse: verse, fetchedAt: Date())
        guard let data = try? JSONEncoder().encode(cached) else { return }
        defaults.set(data, forKey: key)
    }
}
