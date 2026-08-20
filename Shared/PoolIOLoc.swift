import Foundation

/// Strings for pool import/export — the Track 3 half of the Verses tab (see
/// docs/verse-pool-contracts.md's Strings section for why every feature keeps
/// its own `LocalizedKeySet` rather than adding cases to `Loc`).
///
/// Kept independent of `NSAlert`'s own default button titles ("OK", "Cancel")
/// deliberately: those come from macOS's own localization of the *system*
/// locale, which is not what `AppSettings.language` switches, so an app whose
/// interface language differs from the Mac's would otherwise show an
/// English/system alert body next to a mismatched system button. Every button
/// this file's UI presents is spelled out here instead.
enum PoolIOLoc: String, LocalizedKeySet {
    // MARK: Verses tab row
    case importEllipsis
    case exportEllipsis
    case importFromClipboard

    // MARK: Export panel
    case exportFormatBibliadaPool
    case exportFormatPlainText
    case exportFormatLabel

    // MARK: Alerts — shared buttons
    case ok
    case cancel

    // MARK: Import success
    case importSucceededTitle
    /// "Imported \"%@\" — %d verses." — pool name, verse count.
    case importSucceededMessage
    /// "%d reference(s) aren't in %@:" — count, translation id. Prefixes the
    /// missing-reference list in the same alert.
    case importMissingInTranslation
    /// "%d line(s) couldn't be read:" — count. Prefixes the failed-line list.
    case importLinesFailed

    // MARK: Import failure
    case importFailedTitle
    case importRefusedEmptyTitle
    /// Body for `importRefusedEmptyTitle`: explains the guardrail rather than
    /// just saying no.
    case importRefusedEmptyMessage
    case errorNotAnObject
    case errorMissingName
    case errorMissingRules
    case errorNoRules
    /// "\"%@\" isn't a valid verse range." — the offending range key.
    case errorInvalidRange
    case errorUnreadable

    // MARK: Naming an import
    /// Default name offered for a pool imported from a `.bibliadapool` file
    /// that is itself missing/blank — should not happen given
    /// `PoolDocumentError.missingName`, but a plain-text import has no name
    /// of its own to fall back on.
    case importedPoolDefaultName
    /// Default name for a pool built from the pasteboard.
    case pastedPoolDefaultName

    static let table: [PoolIOLoc: [AppLanguage: String]] = [
        .importEllipsis: [.en: "Import…", .uk: "Імпорт…"],
        .exportEllipsis: [.en: "Export…", .uk: "Експорт…"],
        .importFromClipboard: [.en: "Import from Clipboard", .uk: "Імпортувати з буфера обміну"],

        .exportFormatBibliadaPool: [.en: "Bibliada Pool (.bibliadapool)", .uk: "Пул Bibliada (.bibliadapool)"],
        .exportFormatPlainText: [.en: "Plain Text (.txt)", .uk: "Звичайний текст (.txt)"],
        .exportFormatLabel: [.en: "Format:", .uk: "Формат:"],

        .ok: [.en: "OK", .uk: "Гаразд"],
        .cancel: [.en: "Cancel", .uk: "Скасувати"],

        .importSucceededTitle: [.en: "Pool Imported", .uk: "Пул імпортовано"],
        .importSucceededMessage: [.en: "Imported \"%@\" — %d verse(s).", .uk: "Імпортовано «%@» — %d вірш(ів)."],
        .importMissingInTranslation: [
            .en: "%d reference(s) aren't in %@:",
            .uk: "%d посилання відсутні в %@:",
        ],
        .importLinesFailed: [.en: "%d line(s) couldn't be read:", .uk: "%d рядок(ків) не вдалося прочитати:"],

        .importFailedTitle: [.en: "Couldn't Import Pool", .uk: "Не вдалося імпортувати пул"],
        .importRefusedEmptyTitle: [.en: "Nothing to Import", .uk: "Нічого імпортувати"],
        .importRefusedEmptyMessage: [
            .en: "This resolves to no verses in the current translation, so no pool was created. "
                + "Check the references and try again.",
            .uk: "Це не відповідає жодному віршу в поточному перекладі, тому пул не створено. "
                + "Перевірте посилання й спробуйте ще раз.",
        ],
        .errorNotAnObject: [
            .en: "That file isn't a valid .bibliadapool document.",
            .uk: "Цей файл не є дійсним документом .bibliadapool.",
        ],
        .errorMissingName: [.en: "The pool file is missing its \"name\".", .uk: "У файлі пулу відсутнє поле «name»."],
        .errorMissingRules: [.en: "The pool file is missing its \"rules\" list.", .uk: "У файлі пулу відсутній список «rules»."],
        .errorNoRules: [.en: "The pool file's \"rules\" list is empty.", .uk: "Список «rules» у файлі пулу порожній."],
        .errorInvalidRange: [.en: "\"%@\" isn't a valid verse range.", .uk: "«%@» не є дійсним діапазоном віршів."],
        .errorUnreadable: [.en: "That file couldn't be read.", .uk: "Не вдалося прочитати цей файл."],

        .importedPoolDefaultName: [.en: "Imported pool", .uk: "Імпортований пул"],
        .pastedPoolDefaultName: [.en: "Pasted verses", .uk: "Вставлені вірші"],
    ]
}
