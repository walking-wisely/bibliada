import SwiftUI

/// The verse card as the desktop overlay presents it: the shared `VerseCardView`
/// plus a right-click menu.
///
/// The menu exists mainly for locking. Once the card is where you want it, the
/// natural gesture is to right-click the thing itself and say "stay there" —
/// going to Settings to protect a position you just set by dragging is a detour.
///
/// Unlocking, though, can never live only here: a locked card ignores the mouse,
/// which includes the right-click that would open this menu. So the same toggle
/// is in the menu-bar menu and in Settings, and those are the ways back.
struct OverlayCardView: View {
    let verse: Verse
    let settings: AppSettings

    var body: some View {
        VerseCardView(verse: verse, settings: settings)
            .contextMenu {
                Toggle(settings.language.t(.lockPosition), isOn: Self.positionLockedBinding)
                Button(settings.language.t(.newVerseNow)) {
                    AppState.shared.refreshNow()
                }

                Divider()

                addToPoolMenu
                Button(settings.language.t(PoolBrowserLoc.menuExcludeThisVerse)) {
                    excludeCurrentVerse()
                }
                .disabled(excludeTargetPool == nil)
            }
    }

    /// "Add to pool ▸ [pool]" — one item per user-created pool. The built-in
    /// curated pool never appears here: `VersePoolStore.append` is a no-op for
    /// it (see `VersePoolStore.update`), so offering it would silently do
    /// nothing.
    @ViewBuilder
    private var addToPoolMenu: some View {
        let pools = VersePoolStore.shared.pools
        Menu(settings.language.t(PoolBrowserLoc.menuAddCurrentVerseTo)) {
            if pools.isEmpty {
                Text(settings.language.t(PoolBrowserLoc.menuNoPoolsYet))
            } else {
                ForEach(pools) { pool in
                    Button(pool.name) {
                        addCurrentVerse(toPoolWithID: pool.id)
                    }
                }
            }
        }
    }

    /// The pool "Exclude this verse" writes into: the active pool, but only
    /// when it's user-created. The active pool can be the built-in curated
    /// one (no pool selected yet), which can't be mutated, so the menu item
    /// disables instead of silently doing nothing.
    private var excludeTargetPool: VersePool? {
        let pool = VersePoolStore.shared.activePool(settings: settings)
        return pool.isBuiltIn ? nil : pool
    }

    /// The card's `verse.reference` is a display string ("John 3:16"), not a
    /// canonical `VerseReference` — reparsing it through `ReferenceParser`
    /// reuses the one parser that already knows every bundled translation's
    /// book names, rather than teaching this view its own book-name lookup.
    private func currentRange() -> VerseRange? {
        ReferenceParser.parseOne(verse.reference)
    }

    private func addCurrentVerse(toPoolWithID id: UUID) {
        guard let range = currentRange() else { return }
        VersePoolStore.shared.append(rule: PoolRule(range: range), toPoolWithID: id)
    }

    private func excludeCurrentVerse() {
        guard let pool = excludeTargetPool, let range = currentRange() else { return }
        VersePoolStore.shared.append(rule: PoolRule(range: range, isExclusion: true), toPoolWithID: pool.id)
    }

    /// Reads and writes the live store rather than a passed-in binding: this view
    /// is handed to an `NSHostingView` and rebuilt whenever settings change, so a
    /// captured binding would be a snapshot.
    static var positionLockedBinding: Binding<Bool> {
        Binding(
            get: { SettingsStore.shared.settings.positionLocked },
            set: { newValue in
                var settings = SettingsStore.shared.settings
                settings.positionLocked = newValue
                SettingsStore.shared.settings = settings
            }
        )
    }
}
