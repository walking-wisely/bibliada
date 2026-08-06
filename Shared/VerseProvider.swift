import Foundation

/// Fetches a random verse from bible-api.com (World English Bible), falling
/// back to the bundled catalog on any failure. Also responsible for decoding
/// and caching the bundled catalog itself.
actor VerseProvider {
    static let shared = VerseProvider()

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 8
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// Response shape returned by `GET https://bible-api.com/<reference>?translation=web`.
    private struct BibleAPIResponse: Decodable {
        let reference: String
        let text: String
        let translation_id: String
    }

    /// Picks a random reference (avoiding the one currently cached, when
    /// possible), fetches its WEB text from bible-api.com, and caches the
    /// result. Never throws; on any failure returns the bundled entry for
    /// whichever reference was chosen.
    func nextVerse() async -> Verse {
        let catalog = Self.catalog
        guard !catalog.isEmpty else {
            let placeholder = Verse(reference: "", text: "", translation: "WEB")
            VerseCache.save(placeholder)
            return placeholder
        }

        let currentReference = VerseCache.load()?.verse.reference
        let candidate = Self.pickCandidate(from: catalog, avoiding: currentReference)

        let fetched = await Self.fetchWithRetry(reference: candidate.reference)
        let result = fetched ?? candidate
        VerseCache.save(result)
        return result
    }

    /// Synchronous, offline, cheap. Used for widget previews/placeholders.
    static func bundledRandom() -> Verse {
        let catalog = Self.catalog
        return catalog.randomElement() ?? Verse(
            reference: "John 3:16",
            text: "For God so loved the world, that he gave his one and only Son, that whoever believes in him should not perish, but have eternal life.",
            translation: "WEB"
        )
    }

    /// Decoded from `Resources/verses.json`, cached after first access.
    static var catalog: [Verse] {
        catalogStorage.value
    }

    private static let catalogStorage = CatalogBox()

    private final class CatalogBox: @unchecked Sendable {
        private let lock = NSLock()
        private var cached: [Verse]?

        var value: [Verse] {
            lock.lock()
            defer { lock.unlock() }
            if let cached { return cached }
            let loaded = Self.load()
            cached = loaded
            return loaded
        }

        private static func load() -> [Verse] {
            let bundle = Bundle(for: BundleToken.self)
            guard let url = bundle.url(forResource: "verses", withExtension: "json") else {
                return []
            }
            guard let data = try? Data(contentsOf: url) else { return [] }
            guard let verses = try? JSONDecoder().decode([Verse].self, from: data) else { return [] }
            return verses
        }
    }

    private final class BundleToken {}

    private static func pickCandidate(from catalog: [Verse], avoiding reference: String?) -> Verse {
        guard catalog.count > 1, let reference else {
            return catalog.randomElement() ?? catalog[0]
        }
        var candidate = catalog.randomElement() ?? catalog[0]
        var attempts = 0
        while candidate.reference == reference, attempts < 10 {
            candidate = catalog.randomElement() ?? catalog[0]
            attempts += 1
        }
        return candidate
    }

    private static func fetchWithRetry(reference: String) async -> Verse? {
        if let verse = await fetchOnce(reference: reference) {
            return verse
        }
        return await fetchOnce(reference: reference)
    }

    private static func fetchOnce(reference: String) async -> Verse? {
        guard let url = makeURL(reference: reference) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.httpMethod = "GET"

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(BibleAPIResponse.self, from: data)
            let normalized = normalize(decoded.text)
            guard !normalized.isEmpty else { return nil }
            return Verse(reference: decoded.reference, text: normalized, translation: "WEB")
        } catch {
            return nil
        }
    }

    private static func makeURL(reference: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "bible-api.com"
        components.path = "/" + reference
        components.queryItems = [URLQueryItem(name: "translation", value: "web")]
        return components.url
    }

    /// Trims whitespace and collapses any run of whitespace/newlines to a single space.
    private static func normalize(_ text: String) -> String {
        let collapsed = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        return balanceQuotes(trimmed)
    }

    /// Strips a single dangling curly quote left over from fetching one verse in
    /// isolation. bible-api.com returns exactly one verse per request, so a
    /// reference that opens or closes a quotation spanning multiple verses in its
    /// source chapter comes back with an unmatched "“" or "”" — confirmed against
    /// the API's own response, not an artifact of how the catalog was built. Only
    /// a single stray mark is ever removed; text with balanced quotes is untouched.
    private static func balanceQuotes(_ text: String) -> String {
        let opens = text.filter { $0 == "\u{201C}" }.count
        let closes = text.filter { $0 == "\u{201D}" }.count
        guard opens != closes else { return text }
        if opens > closes, let index = text.lastIndex(of: "\u{201C}") {
            var result = text
            result.remove(at: index)
            return result
        }
        if closes > opens, let index = text.firstIndex(of: "\u{201D}") {
            var result = text
            result.remove(at: index)
            return result
        }
        return text
    }
}
