import SwiftUI

/// The Verses settings tab: the pool list, and the entry point into the pool
/// editor. See `docs/verse-pool-customization.md`.
///
/// This file starts as just the extension-point seam — see
/// `docs/verse-pool-contracts.md` — so the import/export track has something
/// to build against before the rest of the tab lands in a later commit.
struct VersesSettingsTab: View {
    @Binding var settings: AppSettings

    var body: some View {
        Text(settings.language.t(PoolLoc.versesTabHeader))
    }

    /// Filled in by the import/export track — the Import…/Export… buttons.
    @ViewBuilder
    static func interchangeControls(store: VersePoolStore, selection: Binding<UUID?>) -> some View {
        EmptyView()
    }
}
