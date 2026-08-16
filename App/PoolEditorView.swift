import SwiftUI

/// The pool editor's body: name field and omnibar on top, the discovery
/// section (browser/search, filled in by Track 2) beneath it, the rule table
/// below that, and a live verse counter with a random preview at the bottom.
/// Hosted by `PoolEditorWindowController` in its own resizable window — see
/// that controller for why it isn't a sheet over Settings.
struct PoolEditorView: View {
    @Binding var pool: VersePool
    let translationID: String
    let language: AppLanguage

    @State private var omnibarText: String = ""
    @State private var omnibarExcludes: Bool = false
    @State private var omnibarFocusToken = 0
    @State private var previewVerse: Verse?

    /// The built-in curated pool can't be edited — `VersePoolStore.update`
    /// silently refuses it — so the editor reflects that instead of letting
    /// every control appear to work and then quietly do nothing.
    private var isReadOnly: Bool { pool.isBuiltIn }

    private var resolvedCount: Int { VersePoolResolver.count(rules: pool.rules) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    omnibarSection
                    Self.discoverySection(pool: $pool, translationID: translationID, language: language)
                    ruleSection
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .frame(
            minWidth: 640, idealWidth: 900, maxWidth: .infinity,
            minHeight: 420, idealHeight: 560, maxHeight: .infinity
        )
        // A hidden, zero-size button is the standard SwiftUI way to attach a
        // window-wide keyboard shortcut that isn't tied to any one visible
        // control — clicking nothing, it exists purely to catch ⌘F and hand
        // focus back to the omnibar from wherever it currently is.
        .background(
            Button("") { omnibarFocusToken += 1 }
                .keyboardShortcut("f", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
        )
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(
                language.t(PoolLoc.poolNameFieldLabel),
                text: Binding(get: { pool.name }, set: { pool.name = $0 })
            )
            .textFieldStyle(.plain)
            .font(.title2.weight(.semibold))
            .disabled(isReadOnly)

            if isReadOnly {
                Text(language.t(PoolLoc.poolEditorReadOnlyHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private var omnibarSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ReferenceOmnibar(
                text: $omnibarText,
                translationID: translationID,
                language: language,
                focusToken: omnibarFocusToken,
                onCommit: handleOmnibarCommit
            )
            .disabled(isReadOnly)

            Toggle(language.t(PoolLoc.ruleTableExclude), isOn: $omnibarExcludes)
                .toggleStyle(.checkbox)
                .font(.caption)
                .foregroundStyle(.secondary)
                .disabled(isReadOnly)
        }
    }

    private var ruleSection: some View {
        PoolRuleTable(pool: $pool, translationID: translationID, language: language, isReadOnly: isReadOnly)
            .frame(minHeight: 220)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(counterText)
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                Spacer()
                Button(language.t(PoolLoc.previewRandomButton), action: rollPreview)
                    .disabled(resolvedCount == 0)
            }

            if resolvedCount == 0 {
                Label(language.t(PoolLoc.verseCounterEmptyWarning), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if resolvedCount < 10 {
                Label(language.t(PoolLoc.verseCounterTinyWarning), systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            previewCard
        }
        .padding(16)
    }

    @ViewBuilder
    private var previewCard: some View {
        if let previewVerse {
            VStack(alignment: .leading, spacing: 4) {
                Text(previewVerse.text)
                    .font(.body)
                Text(previewVerse.reference)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary.opacity(0.4))
            )
        } else if resolvedCount == 0 {
            Text(language.t(PoolLoc.previewRandomEmptyHint))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var counterText: String {
        resolvedCount == 1
            ? language.t(PoolLoc.verseCounterSingular, resolvedCount)
            : language.t(PoolLoc.verseCounterPlural, resolvedCount)
    }

    // MARK: - Actions

    private func handleOmnibarCommit(_ result: ReferenceParseResult) {
        guard !isReadOnly else { return }
        addRules(result.references.map(\.range), isExclusion: omnibarExcludes)
    }

    /// Draws a genuinely random verse from the pool's current resolution —
    /// what the design doc calls "a real card drawn from the current pool" —
    /// retrying a few times if the first pick or two lands on a reference this
    /// translation happens not to contain (see `VersePoolResolver`'s note on
    /// versification gaps).
    private func rollPreview() {
        let references = VersePoolResolver.resolve(rules: pool.rules)
        guard !references.isEmpty else {
            previewVerse = nil
            return
        }
        var attempts = 0
        var verse: Verse?
        while verse == nil, attempts < 10, let reference = references.randomElement() {
            verse = TranslationCatalog.verse(reference: reference, translationID: translationID)
            attempts += 1
        }
        previewVerse = verse
    }

    // MARK: - Extension points (see docs/verse-pool-contracts.md)

    /// The browse-and-search half of the editor, filled in at integration by
    /// `PoolDiscoverySection`. Shipped as `EmptyView()` while the tracks were
    /// building in parallel; `language` joined the signature here because the
    /// two views behind it are localized and a static seam can't reach the
    /// editor's own copy of it.
    @ViewBuilder
    static func discoverySection(
        pool: Binding<VersePool>,
        translationID: String,
        language: AppLanguage
    ) -> some View {
        PoolDiscoverySection(pool: pool, translationID: translationID, language: language)
    }

    /// Called by the browser and search surfaces to add what the user
    /// selected. Track 1 owns the implementation; other tracks only call it.
    func addRules(_ ranges: [VerseRange], isExclusion: Bool) {
        for range in ranges {
            pool.rules.append(PoolRule(range: range, isExclusion: isExclusion))
        }
    }
}
