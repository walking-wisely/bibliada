import Foundation

/// Track 1's own string set — the Verses tab, the pool editor window, the
/// reference omnibar and the rule table. Kept out of `Loc` for the reason
/// `LocalizedKeySet`'s doc comment gives: three tracks editing one enum in one
/// file is a guaranteed merge conflict, so each track owns its own key set
/// and its own table instead.
enum PoolLoc: String, LocalizedKeySet {
    // Settings tab
    case tabVerses

    // Verses settings tab
    case versesTabHeader
    case versesTabFooter
    case poolVerseCount
    case newPool
    case duplicatePool
    case deletePool
    case editPoolEllipsis
    case curatedPoolName
    case deletePoolConfirmTitle
    case deletePoolConfirmMessage
    case deletePoolConfirmDelete
    case deletePoolConfirmCancel
    case newPoolDefaultName

    // Pool editor window
    case poolEditorWindowTitle
    case poolNameFieldLabel
    case poolEditorReadOnlyHint

    // Reference omnibar
    case omnibarPlaceholder
    case omnibarAddButton
    case omnibarParseFailureUnknownBook
    case omnibarParseFailureMalformed
    case omnibarParseFailureOutOfRange
    case omnibarParseFailuresSummary

    // Rule table
    case ruleTableReferenceColumn
    case ruleTableVersesColumn
    case ruleTableIncludeExcludeColumn
    case ruleTableInclude
    case ruleTableExclude
    case ruleTableEmptyHint
    case ruleTableDeleteRow

    // Verse counter / preview
    case verseCounterSingular
    case verseCounterPlural
    case verseCounterEmptyWarning
    case verseCounterTinyWarning
    case previewRandomButton
    case previewRandomEmptyHint

    static let table: [PoolLoc: [AppLanguage: String]] = [
        .tabVerses: [.en: "Verses", .uk: "Вірші"],

        .versesTabHeader: [.en: "Verse pools", .uk: "Набори віршів"],
        .versesTabFooter: [
            .en: "The checked pool is the one the desktop card and widget draw from. The built-in “Curated” pool can be duplicated but not edited or deleted.",
            .uk: "Позначений набір — це той, з якого бере вірші картка робочого столу та віджет. Вбудований набір «Дібрані» можна дублювати, але не редагувати чи видаляти.",
        ],
        .poolVerseCount: [.en: "%d verses", .uk: "%d віршів"],
        .newPool: [.en: "New Pool", .uk: "Новий набір"],
        .duplicatePool: [.en: "Duplicate", .uk: "Дублювати"],
        .deletePool: [.en: "Delete", .uk: "Видалити"],
        .editPoolEllipsis: [.en: "Edit…", .uk: "Редагувати…"],
        .curatedPoolName: [.en: "Curated", .uk: "Дібрані"],
        .deletePoolConfirmTitle: [.en: "Delete this pool?", .uk: "Видалити цей набір?"],
        .deletePoolConfirmMessage: [
            .en: "This can't be undone. If this pool is currently active, selection falls back to the curated pool.",
            .uk: "Це неможливо скасувати. Якщо цей набір активний зараз, вибір повернеться до набору «Дібрані».",
        ],
        .deletePoolConfirmDelete: [.en: "Delete", .uk: "Видалити"],
        .deletePoolConfirmCancel: [.en: "Cancel", .uk: "Скасувати"],
        .newPoolDefaultName: [.en: "New Pool", .uk: "Новий набір"],

        .poolEditorWindowTitle: [.en: "Edit Pool", .uk: "Редагування набору"],
        .poolNameFieldLabel: [.en: "Name", .uk: "Назва"],
        .poolEditorReadOnlyHint: [
            .en: "The built-in Curated pool can't be edited. Duplicate it from the Verses tab to make changes.",
            .uk: "Вбудований набір «Дібрані» не можна редагувати. Дублюйте його на вкладці «Вірші», щоб вносити зміни.",
        ],

        .omnibarPlaceholder: [.en: "Ps 23; Rom 8:28-39; Jn 3:16", .uk: "Пс 23; Рим 8:28-39; Ів 3:16"],
        .omnibarAddButton: [.en: "Add", .uk: "Додати"],
        .omnibarParseFailureUnknownBook: [.en: "Unrecognized book: “%@”", .uk: "Невідома книга: «%@»"],
        .omnibarParseFailureMalformed: [.en: "Couldn't read: “%@”", .uk: "Не вдалося розпізнати: «%@»"],
        .omnibarParseFailureOutOfRange: [.en: "Out of range: “%@”", .uk: "Поза межами: «%@»"],
        .omnibarParseFailuresSummary: [.en: "%d of %d references didn't parse", .uk: "%d із %d посилань не розпізнано"],

        .ruleTableReferenceColumn: [.en: "Reference", .uk: "Посилання"],
        .ruleTableVersesColumn: [.en: "Verses", .uk: "Вірші"],
        .ruleTableIncludeExcludeColumn: [.en: "", .uk: ""],
        .ruleTableInclude: [.en: "Include", .uk: "Включити"],
        .ruleTableExclude: [.en: "Exclude", .uk: "Виключити"],
        .ruleTableEmptyHint: [
            .en: "No rules yet. Type a reference above, or use the browser and search below.",
            .uk: "Ще немає правил. Введіть посилання вище або скористайтеся оглядачем і пошуком нижче.",
        ],
        .ruleTableDeleteRow: [.en: "Delete", .uk: "Видалити"],

        .verseCounterSingular: [.en: "%d verse", .uk: "%d вірш"],
        .verseCounterPlural: [.en: "%d verses", .uk: "%d віршів"],
        .verseCounterEmptyWarning: [
            .en: "This pool is empty. Selection falls back to the curated pool until it has at least one verse.",
            .uk: "Цей набір порожній. Вибір повернеться до набору «Дібрані», доки в ньому не буде хоча б один вірш.",
        ],
        .verseCounterTinyWarning: [
            .en: "Fewer than 10 verses means heavy repetition.",
            .uk: "Менш ніж 10 віршів означає часті повтори.",
        ],
        .previewRandomButton: [.en: "Preview Random", .uk: "Показати випадковий"],
        .previewRandomEmptyHint: [.en: "Add a rule to preview a verse.", .uk: "Додайте правило, щоб побачити приклад вірша."],
    ]
}
