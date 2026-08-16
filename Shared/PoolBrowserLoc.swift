import Foundation

/// Strings for Track 2's surfaces: the book/chapter/verse browser, full-text
/// search, and the in-context "add to pool" / "exclude" commands. Kept in its
/// own `LocalizedKeySet` rather than added to `Loc` so this file — built
/// concurrently with the editor and the import/export tracks — never
/// conflicts with theirs on the same two lines. See
/// docs/verse-pool-contracts.md.
enum PoolBrowserLoc: String, LocalizedKeySet {
    // Book/chapter/verse browser
    case browserBookHeader
    case browserChapterHeader
    case browserVerseHeader
    case browserSelectBookPrompt
    case browserSelectChapterPrompt
    case browserVerseUnavailable
    case browserAddSelection
    case browserAddWholeChapter
    case browserExcludeToggle

    // Full-text search
    case searchFieldPlaceholder
    case searchNoResults
    case searchNoQuery
    case searchAddAllResults
    case searchAddChecked

    // In-context add/exclude (menu bar + overlay card context menu)
    case menuAddCurrentVerseTo
    case menuExcludeThisVerse
    case menuNoPoolsYet

    static let table: [PoolBrowserLoc: [AppLanguage: String]] = [
        .browserBookHeader: [.en: "Book", .uk: "Книга"],
        .browserChapterHeader: [.en: "Chapter", .uk: "Розділ"],
        .browserVerseHeader: [.en: "Verse", .uk: "Вірш"],
        .browserSelectBookPrompt: [.en: "Select a book", .uk: "Оберіть книгу"],
        .browserSelectChapterPrompt: [.en: "Select a chapter", .uk: "Оберіть розділ"],
        .browserVerseUnavailable: [.en: "(not in this translation)", .uk: "(немає в цьому перекладі)"],
        .browserAddSelection: [.en: "Add selection", .uk: "Додати вибране"],
        .browserAddWholeChapter: [.en: "Add whole chapter", .uk: "Додати весь розділ"],
        .browserExcludeToggle: [.en: "Exclude", .uk: "Виключити"],

        .searchFieldPlaceholder: [.en: "Search verses…", .uk: "Пошук віршів…"],
        .searchNoResults: [.en: "No results", .uk: "Немає результатів"],
        .searchNoQuery: [.en: "Type a word or phrase to search the whole Bible", .uk: "Введіть слово чи фразу для пошуку по всій Біблії"],
        .searchAddAllResults: [.en: "Add all %d results", .uk: "Додати всі %d результатів"],
        .searchAddChecked: [.en: "Add checked (%d)", .uk: "Додати позначені (%d)"],

        .menuAddCurrentVerseTo: [.en: "Add current verse to", .uk: "Додати поточний вірш до"],
        .menuExcludeThisVerse: [.en: "Exclude this verse", .uk: "Виключити цей вірш"],
        .menuNoPoolsYet: [.en: "No pools yet — create one in Settings", .uk: "Ще немає добірок — створіть її в Налаштуваннях"],
    ]
}
