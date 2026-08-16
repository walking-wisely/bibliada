import SwiftUI

/// The editor's discovery half: the book/chapter/verse browser and full-text
/// search, behind a picker, both feeding rules into the pool being edited.
///
/// This is the join between two tracks that were built in parallel — the
/// editor and its rule table on one side, the browser and search on the other
/// (see docs/verse-pool-contracts.md). It exists as its own view rather than
/// as a closure inside `PoolEditorView.discoverySection` because the picker
/// needs somewhere to keep its selection, and a static seam has no state.
///
/// The two surfaces are deliberately mutually exclusive rather than stacked:
/// each wants the full width of the window, and stacking them would push the
/// rule table — which is what the user is actually building — below the fold.
struct PoolDiscoverySection: View {
    @Binding var pool: VersePool
    let translationID: String
    let language: AppLanguage

    private enum Surface: Hashable {
        case browse
        case search
    }

    @State private var surface: Surface = .browse

    /// Mirrors `PoolEditorView.isReadOnly` — the built-in curated pool can't be
    /// edited, so offering controls that silently do nothing would be worse
    /// than not offering them.
    private var isReadOnly: Bool { pool.isBuiltIn }

    var body: some View {
        if !isReadOnly {
            VStack(alignment: .leading, spacing: 10) {
                Picker("", selection: $surface) {
                    Text(language.t(PoolBrowserLoc.discoveryBrowseTab)).tag(Surface.browse)
                    Text(language.t(PoolBrowserLoc.discoverySearchTab)).tag(Surface.search)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                switch surface {
                case .browse:
                    PoolBrowserView(translationID: translationID, language: language, onAdd: add)
                case .search:
                    PoolSearchView(translationID: translationID, language: language, onAdd: add)
                }
            }
        }
    }

    /// Both surfaces hand back ranges the same way, and both land in the same
    /// place as an omnibar entry would — `PoolEditorView.addRules` is the
    /// single path rules take into a pool.
    private func add(_ ranges: [VerseRange], isExclusion: Bool) {
        for range in ranges {
            pool.rules.append(PoolRule(range: range, isExclusion: isExclusion))
        }
    }
}
