import AppIntents
import WidgetKit

/// One rendered moment in the widget's timeline: a verse plus the fully-resolved
/// settings (app settings overlaid with this widget instance's configuration).
struct VerseEntry: TimelineEntry {
    let date: Date
    let verse: Verse
    let settings: AppSettings
}

/// Supplies the widget's timeline entries.
///
/// IMPORTANT (see SPEC.md "Widget mode"): macOS — not this provider — controls the
/// actual reload budget for widgets (roughly 40-70 reloads/day system-wide across
/// all of a user's widgets). Whatever cadence we request here (via the intent's
/// `frequency`, or the app's own `AppSettings.frequency`) is honored only
/// *approximately*; sub-hourly cadences in particular are unlikely to fire as
/// often as configured. This is a known, accepted platform limitation, not a bug
/// in this provider. To make the widget still feel "fresh" even when the system
/// reloads less often than requested, `timeline(for:in:)` below pre-computes
/// several future entries (up to 24, spaced at the resolved interval, covering
/// roughly the next 24 hours) with distinct verses, so WidgetKit can advance
/// through them locally between actual reloads.
struct VerseTimelineProvider: AppIntentTimelineProvider {
    typealias Entry = VerseEntry
    typealias Intent = VerseWidgetConfigurationIntent

    /// Fully offline and instant: no network, no shared-container reads. Used by
    /// the system for widget gallery previews and the redacted "loading" state.
    func placeholder(in context: Context) -> VerseEntry {
        VerseEntry(date: Date(), verse: VerseProvider.bundledRandom(), settings: .default)
    }

    /// A quick, non-network preview shown while the user is configuring the
    /// widget. Prefers the last cached verse (shared between app and widget) and
    /// only falls back to a bundled random verse if nothing has been cached yet.
    /// Deliberately never hits the network here.
    func snapshot(for configuration: VerseWidgetConfigurationIntent, in context: Context) async -> VerseEntry {
        let settings = await effectiveSettings(for: configuration, reloadFirst: false)
        let verse = VerseCache.load()?.verse
            ?? VerseProvider.bundledRandom(enabledTranslations: [settings.translationID])
        return VerseEntry(date: Date(), verse: verse, settings: settings)
    }

    func timeline(for configuration: VerseWidgetConfigurationIntent, in context: Context) async -> Timeline<VerseEntry> {
        // Pick up whatever the main app most recently wrote to the shared
        // container before reading `SettingsStore.shared.settings` below.
        let settings = await effectiveSettings(for: configuration, reloadFirst: true)
        let interval = max(settings.widgetFrequency.interval, 60) // guard against a degenerate 0/negative interval

        // Cap at 24 entries covering ~24h, per the module doc comment above.
        let dayInSeconds: TimeInterval = 24 * 60 * 60
        let entryCount = max(1, min(24, Int(dayInSeconds / interval)))

        // `nextVerse()` never throws — it's a pure offline lookup against the
        // bundled catalog (and always writes `VerseCache`) — so there's no
        // empty-timeline case to guard against here.
        let firstVerse = await VerseProvider.shared.nextVerse(enabledTranslations: [settings.translationID])

        // Build a shuffled pool of *other* curated verses, in the same
        // translation as the entry anchoring this timeline, so subsequent
        // entries visibly rotate between system-triggered reloads.
        var pool = VerseProvider.curatedVerses(translationID: firstVerse.translation).filter { $0 != firstVerse }
        pool.shuffle()

        var entries: [VerseEntry] = [VerseEntry(date: Date(), verse: firstVerse, settings: settings)]
        var entryDate = Date()
        for offset in 1..<entryCount {
            entryDate = entryDate.addingTimeInterval(interval)
            let verse: Verse
            if pool.isEmpty {
                verse = firstVerse
            } else {
                verse = pool[(offset - 1) % pool.count]
            }
            entries.append(VerseEntry(date: entryDate, verse: verse, settings: settings))
        }

        return Timeline(entries: entries, policy: .after(entryDate))
    }

    /// Resolves `AppSettings` for this widget instance: starts from the shared
    /// app settings, then overlays this widget's per-instance intent choices
    /// (theme / frequency / showReference) on top, so an unconfigured widget
    /// behaves exactly like "use app settings" for every field.
    @MainActor
    private func effectiveSettings(for configuration: VerseWidgetConfigurationIntent, reloadFirst: Bool) -> AppSettings {
        if reloadFirst {
            SettingsStore.shared.reload()
        }
        var settings = SettingsStore.shared.settings
        settings.theme = configuration.theme.resolvedTheme()
        settings.showReference = configuration.showReference
        if let frequency = configuration.frequency.updateFrequency {
            settings.refreshMinutes = Int(frequency.interval / 60)
        }
        return settings
    }
}
