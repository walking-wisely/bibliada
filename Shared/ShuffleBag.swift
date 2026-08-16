import Foundation

/// Persisted shuffle-bag state: the fingerprint it was built for, and the
/// verse keys not yet drawn since the last reshuffle. `draw()` pops from the
/// end, so the array is stored in reverse draw order.
struct ShuffleBagState: Codable, Sendable, Equatable {
    let fingerprint: String
    var remaining: [String]
}

/// Exhaust-before-reshuffle verse selection.
///
/// `VerseProvider` used to pick a verse uniformly at random from the active
/// pool, avoiding only the immediately-previous reference. That's adequate at
/// curated-pool scale (178 references) and visibly broken once a pool is
/// small — nothing stops the RNG from showing a 15-verse pool's #3 again two
/// draws after it last appeared. Dealing every reference once in a random
/// order before reshuffling guarantees no repeat until the whole pool has
/// been seen, which is the actual expectation for a hand-picked pool.
///
/// State is persisted in the App Group next to `VerseCache` and
/// `VersePoolStore`, so the app and the widget extension draw from *one* bag
/// rather than each exhausting its own — otherwise the menu bar and a widget
/// showing the same pool would visibly disagree about what "hasn't come up
/// yet" means.
enum ShuffleBag {
    // MARK: - Pure logic

    // Kept free of `UserDefaults`/`AppGroup` so it can run in
    // `scripts/smoke/run.sh`'s throwaway CLI, which exercises this state
    // transition directly (`advance`) rather than through `draw`'s I/O.

    /// Identifies "this exact pool selection": the pool's id, so switching
    /// pools resets the bag, plus a hash of what the pool currently resolves
    /// to, so editing a pool's rules resets the bag even though its id
    /// didn't change. A `Hasher` isn't used here — its seed is randomized per
    /// process, and this fingerprint is compared *across* processes (app vs.
    /// widget extension) via persisted state, so it has to be stable.
    static func fingerprint(pool: VersePool, resolved: [VerseReference]) -> String {
        var hash: UInt64 = 1469598103934665603 // FNV-1a offset basis
        func fold(_ string: String) {
            for byte in string.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 1099511628211 // FNV-1a prime
            }
            hash ^= 0xFF // separator between elements, so "AB","C" != "A","BC"
        }
        fold(pool.id.uuidString)
        for reference in resolved { fold(reference.key) }
        return String(hash, radix: 16)
    }

    /// One draw's state transition: given the previously-persisted state
    /// (nil on the very first draw) and what the pool currently resolves to,
    /// returns the reference to show plus the state to persist next.
    ///
    /// Reshuffles whenever the fingerprint doesn't match the stored one (the
    /// active pool or its rules changed) or the bag is empty (it was fully
    /// dealt). Returns nil only when `resolved` is empty, which callers must
    /// not let happen — see `VersePoolStore.activePool`.
    static func advance(
        _ state: ShuffleBagState?,
        pool: VersePool,
        resolved: [VerseReference]
    ) -> (VerseReference, ShuffleBagState)? {
        guard !resolved.isEmpty else { return nil }
        let fp = fingerprint(pool: pool, resolved: resolved)

        var working: ShuffleBagState
        if let state, state.fingerprint == fp, !state.remaining.isEmpty {
            working = state
        } else {
            working = ShuffleBagState(fingerprint: fp, remaining: resolved.map(\.key).shuffled())
        }

        guard let key = working.remaining.popLast(), let reference = VerseReference(key: key) else {
            return nil
        }
        return (reference, working)
    }

    // MARK: - Persistence

    private static let key = "versePoolShuffleBag.v1"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppGroup.suiteName) ?? .standard
    }

    /// Draws the next reference for `pool`, persisting the resulting bag
    /// state so the next call — from this process or the other one sharing
    /// the App Group — continues from where this one left off.
    static func draw(pool: VersePool, resolved: [VerseReference]) -> VerseReference? {
        guard let (reference, next) = advance(load(), pool: pool, resolved: resolved) else { return nil }
        save(next)
        return reference
    }

    private static func load() -> ShuffleBagState? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ShuffleBagState.self, from: data)
    }

    private static func save(_ state: ShuffleBagState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }
}
