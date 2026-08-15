---
name: overview
description: What Bibliada is and does — a menu-bar macOS app that shows a random public-domain Bible verse on a customizable gradient card, in two display modes (exact-timing desktop overlay, best-effort WidgetKit widget). Start here.
triggers: [bibliada, what does this app do, app overview, display modes, menu bar]
related: [desktop-overlay, widget, settings, verse-source]
---

# Overview

Bibliada is a menu-bar-only macOS app that displays a random Bible verse on a gradient
card. The verse text is public domain (World English Bible). The card's colors, typeface,
size, and refresh cadence are all user-configurable.

The app ships the same card in two different display modes, because macOS imposes very
different constraints on each.

## The two display modes

| | Desktop overlay | WidgetKit widget |
|---|---|---|
| Where it lives | Anywhere on the desktop, at desktop window level | Desktop / Notification Center, via the system widget gallery |
| Size | **Any rectangle**, min 150×150 pt | System families only (small / medium / large / extraLarge) |
| Refresh timing | **Exact**, honored to the minute | Best-effort; macOS decides |
| Configurable from the app | Yes, live | Only when App Group sharing works (see `widget.md`) |

Both modes render the identical `VerseCardView`, so a theme change looks the same in both.

Neither mode can appear on the macOS **Lock Screen** — Apple provides no public API for
that on macOS, unlike iOS.

## Why two modes exist

WidgetKit cannot satisfy two of the app's core requirements:

1. **Arbitrary size.** Widget dimensions are fixed system families. There is no API for a
   custom rectangle.
2. **Exact refresh cadence.** A `TimelineProvider` only *requests* reload times. macOS
   budgets widget reloads to roughly 40–70 per day and decides when they actually happen,
   so sub-hourly refreshes are not deliverable. Calling
   `WidgetCenter.shared.reloadTimelines(ofKind:)` from a background app does not bypass
   this — the budget still applies.

The desktop overlay exists to provide what WidgetKit cannot: it is an ordinary window in a
running app, so it can be any size and can run its own timer. The widget exists because it
is the native, battery-efficient, zero-maintenance option when the coarse cadence is
acceptable.

An alternative approach — compositing the verse into a generated desktop wallpaper image
and calling `NSWorkspace.setDesktopImageURL` — was considered and rejected. It requires
polling for user wallpaper changes, and it breaks Apple's dynamic/video wallpapers by
flattening them to a static frame. The overlay window achieves the same visual result
without fighting the OS.

## The menu bar

The app is `LSUIElement` (see `App/Info.plist`), so there is no Dock icon and no default
window. Everything is reached from the menu bar item (a `book.closed` SF Symbol):

- A live 260×180 preview of the current verse card.
- **New verse now** (⌘N) — fetches immediately, independent of the timer.
- **Show on desktop** — toggles the desktop overlay.
- **Settings…** (⌘,) — opens the Settings window.
- **Quit** (⌘Q).

## Key files

| Path | Role |
|---|---|
| `App/BibliadaApp.swift` | `@main` entry point; `AppDelegate` and `Settings` scene |
| `App/MenuBarController.swift` | Owns the `NSStatusItem`/`NSPopover` menu-bar UI (AppKit, not `MenuBarExtra`, so left- and right-click both open it) |
| `App/AppState.swift` | Current verse, refresh timer, settings reactivity, overlay lifecycle |
| `App/OverlayWindowController.swift` | The desktop overlay window (see `desktop-overlay.md`) |
| `App/SettingsView.swift` | All four settings tabs (see `settings.md`) |
| `Shared/VerseCardView.swift` | The card itself, rendered by both modes |
| `Shared/AppSettings.swift` | The settings model, refresh cadence, `FontChoice` |
| `Shared/SettingsStore.swift` | Persistence + cross-process sharing |
| `Shared/VerseProvider.swift` | Verse fetching and the bundled catalog (see `verse-source.md`) |
| `Widget/` | The WidgetKit extension (see `widget.md`) |

`Shared/` is compiled into **both** the app target and the widget extension target, rather
than being a separate framework — this avoids embedding and signing complexity for a
two-target project.

## Things to know

- **The refresh timer is not a plain repeating `Timer`.** macOS suspends timers across
  sleep. `AppState` re-arms a `Task.sleep` loop after each fire, and separately observes
  `NSWorkspace.didWakeNotification` to check elapsed time on wake and catch up immediately
  if the interval already passed.
- **After every refresh the app asks the widget to reload** via
  `WidgetCenter.shared.reloadTimelines(ofKind: "com.bibliada.verse-widget")`. This is a
  request, not a command — see `widget.md`.
- **Settings changes are observed by polling, not by a publisher.** `AppState` is a plain
  class outside SwiftUI's view-body tracking, and `@Observable` offers no Combine
  publisher to subscribe to, so `observeSettings()` diffs `SettingsStore.shared.settings`
  every 500 ms. It exits early when nothing changed. This matters: see the frame-fighting
  gotcha in `desktop-overlay.md`.
- **The card scales from its container, not from fixed point sizes.** All font sizes and
  padding in `VerseCardView` derive from the shorter side of the available space, so the
  same view reads correctly at 150×150 and at 1400×900.

## Related docs

- `desktop-overlay.md` — the overlay window's behavior, positioning, and Spaces handling
- `widget.md` — the WidgetKit extension and its refresh limitations
- `settings.md` — every setting and the input behaviors
- `verse-source.md` — where verses come from
