import Foundation

/// The interface language: what every label, button and menu item in the app
/// is drawn in. Independent of `AppSettings.translationID` — the language the
/// *Bible verse itself* is shown in — though picking one often suggests the
/// other (see `SettingsView`'s General tab).
///
/// Selected in Settings → General and applied live, without a relaunch: every
/// piece of UI reads it off `AppSettings.language` (via `Loc.t`) rather than
/// through `NSLocalizedString`/String Catalogs, which are tied to the *system*
/// locale and only take effect after the app restarts.
enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case en
    case uk

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .en: return "English"
        case .uk: return "Українська"
        }
    }

    /// The `TranslationMeta.language` code this interface language naturally
    /// pairs with — used to offer switching the Bible translation to match a
    /// newly chosen interface language.
    var translationLanguageCode: String {
        switch self {
        case .en: return "en"
        case .uk: return "uk"
        }
    }

    /// Best guess at start-up: the system's preferred language if Bibliada has
    /// an interface for it, English otherwise.
    static var systemDefault: AppLanguage {
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("uk") ? .uk : .en
    }

    /// Looks up `key`'s text in this language, falling back to English and
    /// then to the key itself so a missing translation degrades to readable
    /// (if untranslated) text instead of a crash.
    func t(_ key: Loc) -> String {
        Loc.table[key]?[self] ?? Loc.table[key]?[.en] ?? key.rawValue
    }

    /// `t(_:)` with `%@`-style placeholders substituted in order via
    /// `String(format:)`.
    func t(_ key: Loc, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }
}

/// Every user-facing string key in the main app UI (menu bar, Settings
/// window, desktop-card context menu). Widget-extension strings are excluded:
/// WidgetKit's own configuration UI is drawn by the system using the
/// standard `Localizable.strings`/String Catalog mechanism tied to the
/// system's language, which this in-app switch has no reach into.
enum Loc: String {
    // Menu bar
    case newVerseNow
    case showVerseOnDesktop
    case lockPosition
    case settingsEllipsis
    case quit

    // Settings window
    case settingsWindowTitle

    // Settings tabs
    case tabAppearance
    case tabSizePosition
    case tabVerseChanges
    case tabGeneral

    // Appearance tab
    case presets
    case startColor
    case endColor
    case direction
    case gradient
    case gradientFooter
    case textSectionHeader
    case font
    case textColor
    case cardSectionHeader
    case cornerRadius
    case opacity
    case textSize
    case stylePreview

    // Size & Position tab
    case placeOnWidgetGrid
    case widgetGridFooter
    case widgetGridFooterShowOverlayHint
    case widgetGridUnavailable
    case sizeSectionHeader
    case sizeFooter
    case width
    case height
    case positionSectionHeader
    case positionFooter
    case xLabel
    case yLabel
    case unlockedHint
    case widgetGridAccessibilityLabel
    case widgetGridAccessibilityHint

    // Verse changes (Updates) tab
    case hours
    case minutes
    case changeVerseEvery
    case changeVerseEveryFooter
    case quickPresets
    case minutesShort
    case hoursShort

    // General tab
    case enableOverlayHint
    case lockedHint
    case showReferenceToggle
    case perWidgetReferenceHint
    case translationsSectionHeader
    case translationsFooter
    case widgetsNotSharedWarning
    case interfaceLanguageSectionHeader
    case languageLabel
    case switchTranslationTitle
    case switchTranslationMessage
    case switchTranslationConfirm
    case switchTranslationKeep

    // Translation picker
    case allLanguages

    static let table: [Loc: [AppLanguage: String]] = [
        .newVerseNow: [.en: "New verse now", .uk: "Новий вірш зараз"],
        .showVerseOnDesktop: [.en: "Show verse on desktop", .uk: "Показувати вірш на робочому столі"],
        .lockPosition: [.en: "Lock position", .uk: "Заблокувати позицію"],
        .settingsEllipsis: [.en: "Settings…", .uk: "Налаштування…"],
        .quit: [.en: "Quit", .uk: "Вийти"],

        .settingsWindowTitle: [.en: "Settings", .uk: "Налаштування"],

        .tabAppearance: [.en: "Appearance", .uk: "Вигляд"],
        .tabSizePosition: [.en: "Size & Position", .uk: "Розмір і позиція"],
        .tabVerseChanges: [.en: "Verse changes", .uk: "Зміна вірша"],
        .tabGeneral: [.en: "General", .uk: "Загальні"],

        .presets: [.en: "Presets", .uk: "Готові стилі"],
        .startColor: [.en: "Start color", .uk: "Початковий колір"],
        .endColor: [.en: "End color", .uk: "Кінцевий колір"],
        .direction: [.en: "Direction", .uk: "Напрямок"],
        .gradient: [.en: "Gradient", .uk: "Градієнт"],
        .gradientFooter: [
            .en: "Direction is the way the colours run: 0° goes from the top down, 90° from the left across.",
            .uk: "Напрямок — це те, як спрямований градієнт: 0° йде згори вниз, 90° — зліва направо.",
        ],
        .textSectionHeader: [.en: "Text", .uk: "Текст"],
        .font: [.en: "Font", .uk: "Шрифт"],
        .textColor: [.en: "Text color", .uk: "Колір тексту"],
        .cardSectionHeader: [.en: "Card", .uk: "Картка"],
        .cornerRadius: [.en: "Corner radius", .uk: "Радіус кутів"],
        .opacity: [.en: "Opacity", .uk: "Непрозорість"],
        .textSize: [.en: "Text size", .uk: "Розмір тексту"],
        .stylePreview: [.en: "Style preview", .uk: "Попередній перегляд стилю"],

        .placeOnWidgetGrid: [.en: "Place on the widget grid", .uk: "Розмістити на сітці віджетів"],
        .widgetGridFooter: [
            .en: "Each cell is one widget slot on the display the card is on. Drag across cells to set the card's size and position in one go, so it lines up with the widgets already sitting there. The outline is where the card is now",
            .uk: "Кожна клітинка — це одне місце для віджета на екрані, де знаходиться картка. Перетягніть через клітинки, щоб одразу задати розмір і позицію картки так, щоб вона вирівнялася з віджетами, що вже там є. Контур показує, де картка зараз",
        ],
        .widgetGridFooterShowOverlayHint: [
            .en: " — switch on “Show verse on desktop” in General to actually see it",
            .uk: " — увімкніть «Показувати вірш на робочому столі» у розділі «Загальні», щоб її побачити",
        ],
        .widgetGridUnavailable: [
            .en: "Widget slot sizes are only known for macOS 26 and later, so there's no grid to line up with on this version. Set the size and position with the fields below.",
            .uk: "Розміри місць для віджетів відомі лише для macOS 26 і новіших версій, тож на цій версії сітки немає. Задайте розмір і позицію полями нижче.",
        ],
        .sizeSectionHeader: [.en: "Size", .uk: "Розмір"],
        .sizeFooter: [
            .en: "Type a size and press Return, or use the arrows to nudge it. Sizes are in points, the same units as the position below — on a Retina display one point covers two pixels. The card is kept inside the usable area of the display it's on, ignoring the menu bar and the Dock, and never goes below %d in either direction.",
            .uk: "Введіть розмір і натисніть Return, або скористайтесь стрілками. Розміри задаються в пунктах — тих самих одиницях, що й позиція нижче: на дисплеї Retina один пункт покриває два пікселі. Картка завжди залишається в межах робочої області екрана, без урахування рядка меню та Dock, і ніколи не буде меншою за %d в жодному напрямку.",
        ],
        .width: [.en: "Width", .uk: "Ширина"],
        .height: [.en: "Height", .uk: "Висота"],
        .positionSectionHeader: [.en: "Position", .uk: "Позиція"],
        .positionFooter: [
            .en: "Where the card's bottom-left corner sits, counted from the bottom-left of your main display: a bigger X moves it right, a bigger Y moves it up. The card is always kept fully on one display, so a value that would push it past an edge is pulled back in. To move it to another display, unlock it and drag it there.",
            .uk: "Де саме знаходиться нижній лівий кут картки, від нижнього лівого кута вашого основного екрана: більше X зсуває картку вправо, більше Y — вгору. Картка завжди повністю залишається на одному екрані, тож значення, яке виштовхнуло б її за межу, буде повернуто назад. Щоб перемістити картку на інший екран, розблокуйте її та перетягніть туди.",
        ],
        .xLabel: [.en: "X", .uk: "X"],
        .yLabel: [.en: "Y", .uk: "Y"],
        .unlockedHint: [
            .en: "While the card is unlocked you can also drag it to move it, or drag its edges to resize it, and wherever you leave it is written back into these fields. It starts out locked — unlock it in General, from the menu-bar menu, or by right-clicking the card. The grid and the fields here work either way.",
            .uk: "Поки картка розблокована, її також можна перетягувати мишею або тягнути за краї, щоб змінити розмір — куди б ви її не залишили, значення запишуться в ці поля. Спочатку вона заблокована — розблокуйте її в розділі «Загальні», у меню в рядку меню або клацнувши правою кнопкою на картці. Сітка й поля нижче працюють в обох випадках.",
        ],
        .widgetGridAccessibilityLabel: [.en: "Widget grid", .uk: "Сітка віджетів"],
        .widgetGridAccessibilityHint: [
            .en: "Drag across cells to size and place the card. The Width, Height, X and Y fields below do the same thing without dragging.",
            .uk: "Перетягніть через клітинки, щоб визначити розмір і позицію картки. Поля «Ширина», «Висота», X та Y нижче роблять те саме без перетягування.",
        ],

        .hours: [.en: "Hours", .uk: "Години"],
        .minutes: [.en: "Minutes", .uk: "Хвилини"],
        .changeVerseEvery: [.en: "Change the verse every", .uk: "Змінювати вірш кожні"],
        .changeVerseEveryFooter: [
            .en: "Anything from 1 minute to 24 hours in total. The verse on your desktop changes exactly this often, because the app keeps its own timer.\n\nWidgets can't be that precise: macOS decides when a widget is allowed to refresh, so a widget rounds this down to one of a few fixed schedules — every hour, every 3, 6 or 12 hours, or once a day. Anything under 3 hours becomes hourly. Right now widgets change %@. A widget you've given its own schedule keeps that instead.",
            .uk: "Від 1 хвилини до 24 годин загалом. Вірш на робочому столі змінюється саме з такою частотою, бо застосунок веде власний таймер.\n\nВіджети не можуть бути такими точними: macOS сама вирішує, коли дозволити віджету оновитися, тож він округлює це значення до одного з кількох фіксованих графіків — щогодини, кожні 3, 6 чи 12 годин, або раз на день. Усе, що менше 3 годин, стає щогодинним. Зараз віджети змінюються %@. Віджет із власним графіком продовжує використовувати його.",
        ],
        .quickPresets: [.en: "Quick presets", .uk: "Швидкі варіанти"],
        .minutesShort: [.en: "min", .uk: "хв"],
        .hoursShort: [.en: "h", .uk: "год"],

        .enableOverlayHint: [
            .en: "Switch on “Show verse on desktop” to place and lock the card.",
            .uk: "Увімкніть «Показувати вірш на робочому столі», щоб розмістити й заблокувати картку.",
        ],
        .lockedHint: [
            .en: "The card stays where it is and clicks pass through it, so it can't be moved or resized by accident. That also means right-clicking it does nothing — unlock it here or from the menu bar. Size and position can still be changed under Size & Position.",
            .uk: "Картка залишається на місці, а кліки проходять крізь неї, тож її не можна випадково перемістити чи змінити розмір. Це також означає, що клацання правою кнопкою на ній нічого не робить — розблокуйте її тут або в меню в рядку меню. Розмір і позицію все ще можна змінити в розділі «Розмір і позиція».",
        ],
        .showReferenceToggle: [.en: "Show verse reference on the desktop card", .uk: "Показувати посилання на вірш на картці робочого столу"],
        .perWidgetReferenceHint: [
            .en: "Each widget has its own setting for the reference, in the widget's own options.",
            .uk: "Кожен віджет має власне налаштування для посилання, у своїх власних параметрах.",
        ],
        .translationsSectionHeader: [.en: "Translations", .uk: "Переклади"],
        .translationsFooter: [
            .en: "Verses come from whichever translation is selected below. Everything is bundled into the app — no network connection needed.",
            .uk: "Вірші беруться з перекладу, обраного нижче. Усе вбудовано в застосунок — інтернет-з'єднання не потрібне.",
        ],
        .widgetsNotSharedWarning: [
            .en: "Widgets can't read your settings on this copy of Bibliada, so they'll show the built-in look instead of your colours, font and card style. The verse on your desktop is unaffected. Installing a signed copy of Bibliada fixes it.",
            .uk: "Віджети не можуть прочитати ваші налаштування на цій копії Bibliada, тож вони показуватимуть вбудований вигляд замість ваших кольорів, шрифту та стилю картки. На вірш на робочому столі це не впливає. Встановлення підписаної копії Bibliada виправляє це.",
        ],
        .interfaceLanguageSectionHeader: [.en: "Language", .uk: "Мова"],
        .languageLabel: [.en: "Interface language", .uk: "Мова інтерфейсу"],
        .switchTranslationTitle: [.en: "Switch Bible translation too?", .uk: "Змінити й переклад Біблії?"],
        .switchTranslationMessage: [
            .en: "You just switched the interface to %@. Switch the Bible translation to %@ as well?",
            .uk: "Ви щойно змінили інтерфейс на %@. Змінити також переклад Біблії на %@?",
        ],
        .switchTranslationConfirm: [.en: "Switch translation", .uk: "Змінити переклад"],
        .switchTranslationKeep: [.en: "Keep current translation", .uk: "Залишити поточний переклад"],

        .allLanguages: [.en: "All languages", .uk: "Усі мови"],
    ]
}
