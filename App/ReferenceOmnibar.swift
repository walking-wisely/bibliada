import SwiftUI

/// The reference omnibar: a token-style field across the top of the pool
/// editor, in the shape of Mail's `To:` field. Type `Ps 23; Rom 8:28-39` and
/// press Return (or click Add) to have every fragment parsed and handed to
/// `onCommit` in one shot.
///
/// One parser backs this field, pasted text, and — once Track 3 lands —
/// plain-text import: `ReferenceParser` lives in `Shared/` for exactly that
/// reason, and this view is nothing but the UI wrapped around it.
struct ReferenceOmnibar: View {
    @Binding var text: String
    let translationID: String
    let language: AppLanguage
    /// Bumped by the editor's hidden ⌘F button to steal focus back to this
    /// field from anywhere else in the window. A plain `Int` rather than a
    /// shared `@FocusState` binding because focus state can't cross view
    /// boundaries without one side owning it — bumping a counter this view
    /// watches is the simplest way to say "focus, now" from outside.
    var focusToken: Int = 0
    var onCommit: (ReferenceParseResult) -> Void

    @FocusState private var isFocused: Bool
    @State private var completions: [CanonBook] = []
    /// Failures from the *last* commit, kept on screen until the next commit
    /// replaces or clears them — the contract that a parse failure is
    /// surfaced, never silently dropped, applies here as much as it does to
    /// plain-text import.
    @State private var lastFailures: [ReferenceParseFailure] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField(language.t(PoolLoc.omnibarPlaceholder), text: $text)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit(commit)
                    .onChange(of: text) { _, newValue in updateCompletions(for: newValue) }
                Button(language.t(PoolLoc.omnibarAddButton), action: commit)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !completions.isEmpty {
                completionsRow
            }

            if !lastFailures.isEmpty {
                failuresView
            }
        }
        .onChange(of: focusToken) { _, _ in isFocused = true }
    }

    private var completionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(completions) { book in
                    Button(book.name(translationID: translationID)) {
                        apply(book)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var failuresView: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lastFailures.enumerated()), id: \.offset) { _, failure in
                Text(message(for: failure))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func message(for failure: ReferenceParseFailure) -> String {
        switch failure.reason {
        case .unknownBook: return language.t(PoolLoc.omnibarParseFailureUnknownBook, failure.source)
        case .malformed: return language.t(PoolLoc.omnibarParseFailureMalformed, failure.source)
        case .outOfRange: return language.t(PoolLoc.omnibarParseFailureOutOfRange, failure.source)
        }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let result = ReferenceParser.parse(trimmed)
        onCommit(result)
        lastFailures = result.failures
        completions = []
        // Fragments that parsed are consumed; anything that failed to parse
        // stays in the field so fixing one typo doesn't mean retyping the
        // whole line.
        text = result.failures.map(\.source).joined(separator: "; ")
    }

    /// The last fragment's book-name part — everything up to its first
    /// digit — which is what `ReferenceParser.completions(for:)` expects.
    /// This mirrors `ReferenceParser`'s own (private) book/number split just
    /// enough to know what the user is mid-typing; it doesn't need to be
    /// exact, only good enough to drive a helpful suggestion list.
    private func updateCompletions(for newValue: String) {
        guard let lastFragment = newValue.split(whereSeparator: { $0 == ";" || $0 == "\n" || $0 == "\r" || $0 == "," }).last else {
            completions = []
            return
        }
        let namePart = String(lastFragment).trimmingCharacters(in: .whitespaces).prefix(while: { !$0.isNumber })
        let matches = ReferenceParser.completions(for: String(namePart))
        // Nothing typed yet, or the fragment already resolved to a single
        // exact book (further typing is chapter/verse numbers): no point
        // showing a suggestion list.
        completions = namePart.trimmingCharacters(in: .whitespaces).isEmpty ? [] : matches
    }

    private func apply(_ book: CanonBook) {
        // Replace the last fragment's name part with the picked book's own
        // display name, leaving any chapter/verse numbers already typed —
        // and any earlier, already-separated fragments — untouched.
        let separators: Set<Character> = [";", "\n", "\r", ","]
        let bookName = book.name(translationID: translationID)
        if let lastSeparatorIndex = text.lastIndex(where: { separators.contains($0) }) {
            let prefix = text[...lastSeparatorIndex]
            let fragment = text[text.index(after: lastSeparatorIndex)...]
            let numberPart = fragment.drop(while: { !$0.isNumber })
            text = "\(prefix) \(bookName)\(numberPart.isEmpty ? "" : " ")\(numberPart)"
        } else {
            let numberPart = text.drop(while: { !$0.isNumber })
            text = "\(bookName)\(numberPart.isEmpty ? "" : " ")\(numberPart)"
        }
        completions = []
        isFocused = true
    }
}
