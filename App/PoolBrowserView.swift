import SwiftUI

/// The pool editor's discovery path: three columns, Book | Chapter | Verse,
/// driven entirely by `BibleCanon` rather than by decoding a translation
/// corpus to draw a list of numbers. See docs/verse-pool-customization.md.
///
/// Standalone and self-contained by design: Track 1 owns the editor window
/// this is meant to sit inside (`PoolEditorView.discoverySection`), but that
/// seam is built concurrently in a separate worktree, so this view takes only
/// a translation id, a language, and a callback rather than reaching into
/// anything Track 1 owns. See docs/verse-pool-contracts.md.
struct PoolBrowserView: View {
    let translationID: String
    let language: AppLanguage
    /// Called with the ranges the user chose to add. `isExclusion` reflects
    /// the "Exclude" toggle at the top of this view, not per-range state —
    /// a browser selection is either all-include or all-exclude at once.
    let onAdd: ([VerseRange], _ isExclusion: Bool) -> Void

    @State private var selectedBookID: String?
    @State private var selectedChapter: Int?
    @State private var selectedVerses: Set<Int> = []
    @State private var isExclusion = false

    private var selectedBook: CanonBook? {
        selectedBookID.flatMap(BibleCanon.book(id:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(language.t(PoolBrowserLoc.browserExcludeToggle), isOn: $isExclusion)
                .toggleStyle(.checkbox)

            HStack(spacing: 0) {
                column(header: .browserBookHeader, width: 170) { bookList }
                Divider()
                column(header: .browserChapterHeader, width: 80) { chapterList }
                Divider()
                column(header: .browserVerseHeader, width: nil) { verseList }
            }
            .frame(minHeight: 260)

            HStack {
                Button(language.t(PoolBrowserLoc.browserAddSelection), action: addSelection)
                    .disabled(selectedBook == nil || selectedChapter == nil || selectedVerses.isEmpty)
                Button(language.t(PoolBrowserLoc.browserAddWholeChapter), action: addWholeChapter)
                    .disabled(selectedBook == nil || selectedChapter == nil)
                Spacer()
            }
        }
        .onChange(of: selectedBookID) { _, _ in
            selectedChapter = nil
            selectedVerses = []
        }
        .onChange(of: selectedChapter) { _, _ in
            selectedVerses = []
        }
    }

    // MARK: - Columns

    @ViewBuilder
    private func column<Content: View>(header: PoolBrowserLoc, width: CGFloat?, @ViewBuilder content: () -> Content) -> some View {
        let labeled = VStack(alignment: .leading, spacing: 4) {
            Text(language.t(header))
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
        if let width {
            labeled.frame(width: width)
        } else {
            labeled.frame(maxWidth: .infinity)
        }
    }

    private var bookList: some View {
        List(BibleCanon.books, selection: $selectedBookID) { book in
            Text(book.name(translationID: translationID))
        }
    }

    private var chapterList: some View {
        Group {
            if let book = selectedBook, book.chapterCount > 0 {
                List(1...book.chapterCount, id: \.self, selection: $selectedChapter) { chapter in
                    Text("\(chapter)")
                }
            } else {
                promptList(.browserSelectBookPrompt)
            }
        }
    }

    private var verseList: some View {
        Group {
            if let book = selectedBook, let chapter = selectedChapter {
                let count = book.verseCount(chapter: chapter)
                if count > 0 {
                    List(1...count, id: \.self, selection: $selectedVerses) { verse in
                        verseRow(book: book.bookID, chapter: chapter, verse: verse)
                    }
                    // A hidden ⌘A button rather than relying on `List`'s own
                    // key handling: SwiftUI's `List` has no public "select
                    // all" API, and the platform ⌘A (select-all-text) would
                    // otherwise not touch this list's selection at all.
                    .background(
                        Button("") { selectedVerses = Set(1...count) }
                            .keyboardShortcut("a", modifiers: .command)
                            .opacity(0)
                            .allowsHitTesting(false)
                    )
                } else {
                    promptList(.browserSelectChapterPrompt)
                }
            } else {
                promptList(.browserSelectChapterPrompt)
            }
        }
    }

    private func promptList(_ prompt: PoolBrowserLoc) -> some View {
        VStack {
            Spacer()
            Text(language.t(prompt))
                .foregroundStyle(.secondary)
                .font(.callout)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// One verse row: number plus its text truncated to one line — bare verse
    /// numbers are the standard failure mode of this UI, since nobody
    /// remembers what Romans 8:31 says by number alone. `translationID` is a
    /// union-canon lookup that can come back nil (a versification gap in this
    /// particular translation); the row still shows and stays selectable,
    /// since the range it adds isn't translation-specific.
    private func verseRow(book: String, chapter: Int, verse: Int) -> some View {
        let text = TranslationCatalog.verse(
            reference: VerseReference(book: book, chapter: chapter, verse: verse),
            translationID: translationID
        )?.text
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(verse)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
            Text(text ?? language.t(PoolBrowserLoc.browserVerseUnavailable))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(text == nil ? .tertiary : .primary)
        }
    }

    // MARK: - Actions

    private func addSelection() {
        guard let book = selectedBook, let chapter = selectedChapter, !selectedVerses.isEmpty else { return }
        onAdd(Self.mergedRanges(book: book.bookID, chapter: chapter, verses: selectedVerses), isExclusion)
    }

    private func addWholeChapter() {
        guard let book = selectedBook, let chapter = selectedChapter else { return }
        // One chapter-level range, not one rule per verse: "Add whole
        // chapter" on Psalm 119 must not turn into 176 rows in the table.
        onAdd([VerseRange(book: book.bookID, chapter: chapter)], isExclusion)
    }

    /// Selected verse numbers collapse into contiguous spans — a multi-select
    /// of 4, 5, 6, 9 becomes two ranges (4-6, 9) instead of four single-verse
    /// ones, so the rule table (and an exported pool) stays as compact as the
    /// underlying selection actually is.
    static func mergedRanges(book: String, chapter: Int, verses: Set<Int>) -> [VerseRange] {
        let sorted = verses.sorted()
        var ranges: [VerseRange] = []
        var start: Int?
        var previous: Int?
        for verse in sorted {
            if let prev = previous, verse == prev + 1 {
                previous = verse
                continue
            }
            if let start, let previous {
                ranges.append(VerseRange(book: book, chapter: chapter, verses: start...previous))
            }
            start = verse
            previous = verse
        }
        if let start, let previous {
            ranges.append(VerseRange(book: book, chapter: chapter, verses: start...previous))
        }
        return ranges
    }
}
