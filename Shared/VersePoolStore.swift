import Foundation
import Observation

/// Persists the user's verse pools to the shared App Group container, next to
/// `SettingsStore` and `VerseCache`, so the widget extension selects from the
/// same pool the app does.
///
/// Degrades to `UserDefaults.standard` when the App Group is unavailable, on
/// the same round-trip probe `SettingsStore.isUsable` uses and for the same
/// reason (a denied group domain still hands back a usable-looking object and
/// silently drops writes).
///
/// The built-in curated pool is never stored — it's rebuilt from
/// `curated-references.json` on demand and prepended to whatever the user has
/// created, so the curated list stays a data file rather than a copy in
/// defaults that could drift from it.
@MainActor
@Observable
final class VersePoolStore {
    static let shared = VersePoolStore()

    private static let poolsKey = "versePools.v1"
    private static let probeKey = "versePoolsDomainProbe"

    private let defaults: UserDefaults

    /// User-created pools, in the order they appear in the Verses tab. The
    /// built-in curated pool is not in here — see `allPools`.
    var pools: [VersePool] {
        didSet { persist() }
    }

    /// Curated first, then the user's own.
    var allPools: [VersePool] { [VersePool.curated] + pools }

    private init() {
        if let shared = UserDefaults(suiteName: AppGroup.suiteName), Self.isUsable(shared) {
            defaults = shared
        } else {
            defaults = .standard
        }
        pools = Self.read(from: defaults) ?? []
    }

    /// Re-reads from disk. The widget calls this at the start of every timeline
    /// computation, mirroring `SettingsStore.reload`.
    func reload() {
        pools = Self.read(from: defaults) ?? []
    }

    // MARK: - Lookup

    func pool(id: UUID?) -> VersePool? {
        guard let id else { return nil }
        return allPools.first { $0.id == id }
    }

    /// The pool selection should currently draw from: the one named by
    /// `AppSettings.activePoolID`, falling back to curated when that id is
    /// unknown (deleted pool, blob from another machine) or when the named pool
    /// resolves to nothing.
    ///
    /// Never returns an empty pool — `TranslationCatalog.randomVerse` contracts
    /// to always return a verse, and an empty pool would break that.
    func activePool(settings: AppSettings) -> VersePool {
        guard let pool = pool(id: settings.activePoolID),
              !VersePoolResolver.resolve(rules: pool.rules).isEmpty else {
            return .curated
        }
        return pool
    }

    // MARK: - Mutation

    func add(_ pool: VersePool) {
        pools.append(pool)
    }

    /// No-op for the built-in pool, which cannot be edited.
    func update(_ pool: VersePool) {
        guard !pool.isBuiltIn, let index = pools.firstIndex(where: { $0.id == pool.id }) else { return }
        pools[index] = pool
    }

    func delete(id: UUID) {
        pools.removeAll { $0.id == id && !$0.isBuiltIn }
    }

    /// A copy under a new id, named "<name> copy" — the only way to get an
    /// editable version of the curated pool.
    func duplicate(_ pool: VersePool) -> VersePool {
        let copy = VersePool(name: "\(pool.name) copy", rules: pool.rules)
        add(copy)
        return copy
    }

    /// Appends a rule to a pool by id and persists. The in-context "Add to
    /// pool" / "Exclude this verse" commands go through here.
    func append(rule: PoolRule, toPoolWithID id: UUID) {
        guard let index = pools.firstIndex(where: { $0.id == id }) else { return }
        pools[index].rules.append(rule)
    }

    // MARK: - Private

    private static func isUsable(_ defaults: UserDefaults) -> Bool {
        let token = UUID().uuidString
        defaults.set(token, forKey: probeKey)
        let readBack = defaults.string(forKey: probeKey)
        defaults.removeObject(forKey: probeKey)
        return readBack == token
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(pools) else { return }
        defaults.set(data, forKey: Self.poolsKey)
    }

    private static func read(from defaults: UserDefaults) -> [VersePool]? {
        guard let data = defaults.data(forKey: poolsKey) else { return nil }
        return try? JSONDecoder().decode([VersePool].self, from: data)
    }
}
