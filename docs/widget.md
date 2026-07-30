---
name: widget
description: How the WidgetKit widget works — its per-instance AppIntent configuration (theme, frequency, show-reference), the multi-entry timeline, why its refresh cadence is only best-effort, and the App Group signing requirement that gates app-to-widget settings sharing.
triggers: [widget, widgetkit, timeline, app intent, app group, signing, team id, refresh budget, widget gallery]
related: [overview, desktop-overlay, settings]
---

# WidgetKit widget

A native macOS widget (Desktop / Notification Center) rendering the same `VerseCardView` as
the desktop overlay. Added from the system widget gallery.

- Widget `kind`: `com.bibliada.verse-widget`
- Bundle id: `com.bibliada.Bibliada.Widget`
- Supported families: `systemSmall`, `systemMedium`, `systemLarge`, `systemExtraLarge`
- `containerBackgroundRemovable(false)` — the gradient *is* the widget

## Refresh cadence is best-effort, by design

This is the single most important thing to understand about the widget, and it is not a bug.

`VerseTimelineProvider` requests reload times, but macOS controls whether they happen. The
system budgets widget reloads to roughly 40–70 per day and schedules them opportunistically
based on battery, connectivity, and how often the user actually looks at the widget. Two
consequences:

- **Sub-hourly refreshes are not deliverable.** `AppSettings.widgetFrequency` floors
  anything under an hour at hourly rather than pretending otherwise.
- **Forcing updates does not work.** `WidgetCenter.shared.reloadTimelines(ofKind:)` — which
  `AppState.performRefresh()` calls after every refresh — is a *request*. It only bypasses
  the budget when the containing app is in the foreground or an App Intent ran. A background
  app firing it on a timer gets throttled. Push-based reloads are budgeted too.

If exact timing matters, that's what the desktop overlay is for. See `desktop-overlay.md`.

### Cadence mapping

The app stores a free-form `refreshMinutes`; `AppSettings.widgetFrequency` rounds it down to
the nearest cadence WidgetKit can plausibly deliver:

| `refreshMinutes` | `widgetFrequency` |
|---|---|
| < 180 | `.hourly` |
| < 360 | `.every3Hours` |
| < 720 | `.every6Hours` |
| < 1440 | `.every12Hours` |
| 1440 | `.daily` |

Settings → Updates displays which cadence the current setting maps to.

## Per-instance configuration

Each placed widget instance is configured through `VerseWidgetConfigurationIntent`
(`WidgetConfigurationIntent`, used via `AppIntentConfiguration`) in the system's "Edit
Widget" UI:

| Parameter | Type | Default |
|---|---|---|
| Theme | `ThemeEntity` (an `AppEntity`) | "Use App Settings" |
| Update Frequency | `FrequencyOption` (an `AppEnum`) | "Use App Settings" |
| Show Reference | `Bool` | `true` |

`ThemeEntity` is built **at runtime** from `GradientTheme.presets` via `ThemeEntityQuery`
rather than hardcoding preset names as enum cases, so the configuration UI can't fall out of
sync when presets are added or renamed. A reserved sentinel id (`__useAppSettings__`) means
"read the app's current theme".

### Intent-vs-app-settings precedence

`effectiveSettings(for:reloadFirst:)` in `VerseTimelineProvider` starts from
`SettingsStore.shared.settings` and overlays the per-instance choices:

- **Theme** — `ThemeEntity.resolvedTheme()`. Falls back to the app's theme for the sentinel
  *or* for a preset name that no longer exists (e.g. presets changed across an update).
- **Frequency** — applied only when `FrequencyOption.updateFrequency` is non-`nil`; the
  sentinel keeps the app's cadence.
- **Show Reference** — always overlaid; it's a plain `Bool` with no sentinel.

`AppSettings.cornerRadius` and `AppSettings.overlayFrame` are **intentionally ignored** here:
widget corner radius and size come from the system.

## The timeline

`VerseTimelineProvider` is an `AppIntentTimelineProvider`:

| Method | Behavior |
|---|---|
| `placeholder` | `VerseProvider.bundledRandom()` — offline and instant |
| `snapshot` | `VerseCache.load()?.verse`, else `bundledRandom()`. **Never** hits the network |
| `timeline` | Calls `SettingsStore.shared.reload()` first, then `await VerseProvider.shared.nextVerse()` |

`timeline` builds **multiple** entries — one per interval, capped at 24, covering roughly the
next 24 hours — with distinct verses drawn from `VerseProvider.catalog` for the future
entries. This means the widget still rotates verses even if the system doesn't reload it on
schedule. The reload policy is `.after(<last entry date>)`. A failed fetch falls back to
cached or bundled verses rather than producing an empty timeline.

## App Group sharing (signing requirement)

The widget extension is sandboxed, so the only way it can read settings written by the app is
through the App Group `group.com.bibliada.shared`. **App Groups require a real Apple
Developer Team ID.**

- With `BIBLIADA_TEAM_ID` set to a real team: normal signing, entitlements granted, the
  widget reflects the theme/cadence chosen in the app.
- Without it: `build.sh` appends `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`, because
  `xcodebuild` otherwise refuses to build at all once App Group entitlements are present
  ("has entitlements that require signing with a development certificate"). The app runs
  fine, the overlay is fully functional, but the widget falls back to its own defaults.

`SettingsStore.isShared` is meant to signal this, and Settings → General shows a warning when
it is `false`.

**Known issue:** `isShared` is unreliable on macOS. `UserDefaults(suiteName:)` succeeds even
without the entitlement for the *non-sandboxed* app — it just writes
`~/Library/Preferences/group.com.bibliada.shared.plist` — so `isShared` reports `true` and
**the warning does not appear** even in unsigned builds. The underlying limitation is
unchanged (the sandboxed widget still can't reach that container), but the warning cannot be
trusted as a diagnostic. A reliable check would have to be made from the widget side.

## Constraints

- **No custom sizes.** System families only. This is the reason the desktop overlay exists.
- **Sandboxed.** Only App Group access and `com.apple.security.network.client`.
- **Requires a signed, LaunchServices-registered app** to appear in the widget gallery.

## Key files

| Path | Role |
|---|---|
| `Widget/BibliadaWidgetBundle.swift` | `@main` `WidgetBundle`, the `Widget` declaration, entry view, container background |
| `Widget/VerseTimelineProvider.swift` | Placeholder / snapshot / timeline, settings-vs-intent merging |
| `Widget/VerseWidgetConfiguration.swift` | `ThemeEntity`, `ThemeEntityQuery`, `FrequencyOption`, the configuration intent |
| `Widget/BibliadaWidget.entitlements` | Sandbox + App Group + network client |
| `Shared/AppSettings.swift` | `widgetFrequency` mapping |

## Things to know

- **`Shared/Resources/verses.json` is bundled into both targets**, and
  `VerseProvider.catalog` locates it via `Bundle(for: BundleToken.self)` rather than
  `Bundle.main`. In an extension, `Bundle.main` is the *extension's* bundle, so `Bundle(for:)`
  is what makes the same code work in both processes.
- **App Intents `static` members must be `let`, not `var`.** Swift 6 strict concurrency
  rejects `static var typeDisplayRepresentation` / `caseDisplayRepresentations` / `title` /
  `description` as nonisolated global mutable state.

## Related docs

- `overview.md` — why there are two display modes
- `desktop-overlay.md` — the exact-timing alternative
- `settings.md` — what the app-side settings control
