import AppIntents
import WidgetKit

// MARK: - Theme selection

/// A selectable gradient theme for a widget instance's configuration UI.
///
/// This mirrors `GradientTheme.presets` (from `Shared/GradientTheme.swift`) at
/// *runtime* via `ThemeEntityQuery`, rather than hardcoding each preset name as a
/// fixed `AppEnum` case. That way the configuration UI never falls out of sync if
/// presets are added/renamed/removed in `Shared/GradientTheme.swift`. One extra
/// sentinel entity (`useAppSettings`) represents "use whatever theme is currently
/// set in the main app's settings" and is the default selection.
struct ThemeEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Colours"
    static let defaultQuery = ThemeEntityQuery()

    /// Either a `GradientTheme.presets` preset name, or `Self.useAppSettingsID`.
    let id: String

    var displayRepresentation: DisplayRepresentation {
        let title = id == Self.useAppSettingsID ? "Match the app" : id
        return DisplayRepresentation(title: "\(title)")
    }

    /// Sentinel id meaning "don't use a fixed preset; read the app's current theme".
    static let useAppSettingsID = "__useAppSettings__"
    static let useAppSettings = ThemeEntity(id: useAppSettingsID)

    /// Resolves this selection to a concrete `GradientTheme`.
    ///
    /// This is the small resolver the per-instance selection needs, since
    /// `GradientTheme` itself is a struct (not something `AppEntity` can vend
    /// directly): for the sentinel entity, or for a preset name that no longer
    /// exists (e.g. presets changed across an app update), it falls back to
    /// whatever theme is currently in `SettingsStore.shared.settings`.
    @MainActor
    func resolvedTheme() -> GradientTheme {
        guard id != Self.useAppSettingsID else {
            return SettingsStore.shared.settings.theme
        }
        return GradientTheme.presets.first(where: { $0.name == id })?.theme
            ?? SettingsStore.shared.settings.theme
    }
}

struct ThemeEntityQuery: EntityQuery {
    func entities(for identifiers: [ThemeEntity.ID]) async throws -> [ThemeEntity] {
        let all = Self.allEntities()
        return all.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ThemeEntity] {
        Self.allEntities()
    }

    func defaultResult() async -> ThemeEntity? {
        ThemeEntity.useAppSettings
    }

    private static func allEntities() -> [ThemeEntity] {
        [ThemeEntity.useAppSettings] + GradientTheme.presets.map { ThemeEntity(id: $0.name) }
    }
}

// MARK: - Frequency selection

/// Mirrors `UpdateFrequency` (hourly ... daily) for the widget configuration UI,
/// plus a `useAppSettings` sentinel case (the default) meaning "read
/// `SettingsStore.shared.settings.frequency` instead of a fixed per-instance value".
enum FrequencyOption: String, AppEnum {
    case useAppSettings
    case hourly
    case every3Hours
    case every6Hours
    case every12Hours
    case daily

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "How often the verse changes"

    static let caseDisplayRepresentations: [FrequencyOption: DisplayRepresentation] = [
        .useAppSettings: "Match the app",
        .hourly: "Every hour",
        .every3Hours: "Every 3 hours",
        .every6Hours: "Every 6 hours",
        .every12Hours: "Every 12 hours",
        .daily: "Once a day",
    ]

    /// Maps to the shared `UpdateFrequency` enum, or `nil` for the sentinel
    /// meaning "fall back to the app's own configured frequency".
    var updateFrequency: UpdateFrequency? {
        switch self {
        case .useAppSettings: return nil
        case .hourly: return .hourly
        case .every3Hours: return .every3Hours
        case .every6Hours: return .every6Hours
        case .every12Hours: return .every12Hours
        case .daily: return .daily
        }
    }
}

// MARK: - Widget configuration intent

/// Per-widget-instance configuration, edited via the "Edit Widget" UI.
struct VerseWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Verse widget options"
    static let description = IntentDescription(
        "Choose the colours, how often the verse changes, and whether the reference is shown — for this widget only."
    )

    @Parameter(title: "Theme", default: ThemeEntity.useAppSettings)
    var theme: ThemeEntity

    @Parameter(title: "Change verse every", default: .useAppSettings)
    var frequency: FrequencyOption

    @Parameter(title: "Show verse reference", default: true)
    var showReference: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Show a verse in \(\.$theme), changing \(\.$frequency)") {
            \.$showReference
        }
    }
}
