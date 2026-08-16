import SwiftUI

/// The pool editor's body: omnibar on top, discovery section (browser/search,
/// filled in by Track 2) in the middle, rule table and live verse counter at
/// the bottom. Hosted by `PoolEditorWindowController` in its own window.
///
/// This file starts as just the extension-point seam — see
/// `docs/verse-pool-contracts.md` — so Tracks 2 and 3 have something to build
/// against before the rest of the editor lands in a later commit.
struct PoolEditorView: View {
    @Binding var pool: VersePool
    let translationID: String

    var body: some View {
        Text(pool.name)
    }

    /// Filled in by the browser/search track. Track 1 ships this returning
    /// `EmptyView()`; the editor already lays out space for it.
    @ViewBuilder
    static func discoverySection(pool: Binding<VersePool>, translationID: String) -> some View {
        EmptyView()
    }

    /// Called by the browser and search surfaces to add what the user selected.
    /// Track 1 owns the implementation; other tracks only call it.
    func addRules(_ ranges: [VerseRange], isExclusion: Bool) {
        for range in ranges {
            pool.rules.append(PoolRule(range: range, isExclusion: isExclusion))
        }
    }
}
