import SwiftUI

/// The pool editor's third discovery surface: search the bundled corpus,
/// check individual hits or add every result at once. See
/// docs/verse-pool-customization.md.
///
/// Standalone and self-contained, like `PoolBrowserView` — see that file's
/// header and docs/verse-pool-contracts.md's Extension points section for why.
struct PoolSearchView: View {
    let translationID: String
    let language: AppLanguage
    let onAdd: ([VerseRange], _ isExclusion: Bool) -> Void

    @State private var query = ""
    @State private var hits: [VerseSearch.Hit] = []
    @State private var checked: Set<VerseReference> = []
    @State private var isSearching = false
    @State private var isExclusion = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField(language.t(PoolBrowserLoc.searchFieldPlaceholder), text: $query)
                    .textFieldStyle(.roundedBorder)
                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .onChange(of: query) { _, newValue in scheduleSearch(newValue) }

            Toggle(language.t(PoolBrowserLoc.browserExcludeToggle), isOn: $isExclusion)
                .toggleStyle(.checkbox)

            resultsList
                .frame(minHeight: 240)

            HStack {
                Button(language.t(PoolBrowserLoc.searchAddAllResults, hits.count), action: addAll)
                    .disabled(hits.isEmpty)
                Button(language.t(PoolBrowserLoc.searchAddChecked, checked.count), action: addChecked)
                    .disabled(checked.isEmpty)
                Spacer()
            }
        }
        .onDisappear { searchTask?.cancel() }
    }

    @ViewBuilder
    private var resultsList: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            centeredPrompt(language.t(PoolBrowserLoc.searchNoQuery))
        } else if hits.isEmpty, !isSearching {
            centeredPrompt(language.t(PoolBrowserLoc.searchNoResults))
        } else {
            List(hits, id: \.reference) { hit in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Toggle("", isOn: checkedBinding(for: hit.reference))
                        .labelsHidden()
                    Text(ReferenceParser.displayString(for: VerseRange(hit.reference), translationID: translationID))
                        .fontWeight(.medium)
                        .fixedSize()
                    Text(hit.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func centeredPrompt(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .foregroundStyle(.secondary)
                .font(.callout)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func checkedBinding(for reference: VerseReference) -> Binding<Bool> {
        Binding(
            get: { checked.contains(reference) },
            set: { isOn in
                if isOn { checked.insert(reference) } else { checked.remove(reference) }
            }
        )
    }

    /// Debounced: `VerseSearch` is cheap once its per-translation cache is
    /// warm, but there's no reason to run a scan for every intermediate
    /// keystroke of a fast typist. Cancelling the previous task rather than
    /// letting both run also means a stale, slower search can never land
    /// after a newer one and clobber its results.
    private func scheduleSearch(_ newValue: String) {
        searchTask?.cancel()
        checked = []
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            hits = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let results = await VerseSearch.shared.search(trimmed, translationID: translationID)
            guard !Task.isCancelled else { return }
            hits = results
            isSearching = false
        }
    }

    private func addAll() {
        onAdd(hits.map { VerseRange($0.reference) }, isExclusion)
    }

    private func addChecked() {
        onAdd(checked.map(VerseRange.init), isExclusion)
        checked = []
    }
}
