---
name: desktop-overlay
description: How the desktop overlay works — a borderless NSPanel at desktop window level that supports arbitrary sizes, drag/resize with persistence, exact timer refresh, all-Spaces presence, and fading out during Mission Control. Covers the window flags and the frame-fighting gotcha.
triggers: [overlay, desktop widget, NSPanel, window level, spaces, mission control, drag, resize, click-through, snaps back]
related: [overview, settings, widget]
---

# Desktop overlay

The desktop overlay is the "fake widget": a borderless `NSPanel` hosting `VerseCardView`,
pinned above the wallpaper and below ordinary app windows. It is what delivers the two
things WidgetKit cannot — **arbitrary rectangular size** and **exact refresh timing**.

Implemented in `App/OverlayWindowController.swift`. Enabled by
`AppSettings.overlayEnabled`, toggled from the menu bar ("Show on desktop") or Settings →
General.

## Window configuration

All of the following is set in `configurePanel()`. These flags are the fragile part of the
feature; each one is load-bearing.

| Setting | Value | Why |
|---|---|---|
| `styleMask` | `[.borderless, .resizable, .nonactivatingPanel]` | Borderless so no titlebar chrome fights the card's own rounded corners. `.resizable` is required for AppKit to install edge-drag resize handles even with no visible frame. `.nonactivatingPanel` so dragging never steals key focus or foregrounds this app. |
| `level` | `CGWindowLevelForKey(.desktopIconWindow) + 1` | Sits directly above the wallpaper and Finder desktop icons, below every ordinary app window (which start at `.normal`). |
| `collectionBehavior` | `[.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]` | Present on every desktop including ones created after launch. `.ignoresCycle` keeps it out of Cmd-Tab. |
| `isOpaque` / `backgroundColor` / `hasShadow` | `false` / `.clear` / `false` | The card draws its own background, corners, and shadow. |
| `isMovableByWindowBackground` | `true` | Drag the card by its body. |
| `isExcludedFromWindowsMenu` | `true` | Decorative chrome, not a window the user switches to. |
| `animationBehavior` | `.none` | Prevents AppKit's default window animations from interfering with the fade logic. |

### Do not add `.stationary`

`.stationary` lifts a window out of the Space-switch animation. With it set, the card
visibly floats above the desktops while they slide underneath during a four-finger swipe —
it reads as detached from the desktop rather than sitting on it.

### Do not use `.moveToActiveSpace` instead of `.canJoinAllSpaces`

`.moveToActiveSpace` binds the window to a single Space. A newly created desktop then shows
nothing at all until the user switches to it. `.canJoinAllSpaces` is what makes the card
replicate across every desktop the way real widgets do.

## Size and position

- **Any rectangle**, minimum 150×150 pt, enforced by `clampedFrame(_:forFrameOf:)`.
- Drag the body to move; drag the edges to resize.
- The resulting frame is written back to `AppSettings.overlayFrame` and restored on launch.
- Frames are clamped to the nearest screen's `visibleFrame`, so an off-screen or
  disconnected-display position recovers rather than stranding the card. Re-clamped on
  `windowDidChangeScreen`.
- Width/height and X/Y can also be typed exactly in Settings → Size & Position. Position is
  in AppKit screen coordinates: the card's **bottom-left corner**, measured from the
  bottom-left of the main display, so **Y counts upward**.

### Frame persistence

Two paths write the frame, deliberately:

1. **Debounced** (`scheduleFrameSave()`, 400 ms) on `windowDidMove` / `windowDidResize`, so
   a continuous drag doesn't spam `SettingsStore` — which persists synchronously on every
   `didSet`.
2. **Immediate** (`persistFrameNow()`) on drag end (`OverlayPanel.mouseDown` returning) and
   `windowDidEndLiveResize`, so no settings-poll tick can ever observe a stale frame.

## Mission Control and Exposé

Real desktop widgets hide while Mission Control is up. macOS exposes **no public API** for
"Mission Control is active", so the overlay uses a heuristic: Mission Control, App Exposé,
and Launchpad all activate the **Dock** (`com.apple.dock`) as the frontmost application.

`observeMissionControl()` watches `NSWorkspace.didActivateApplicationNotification` and sets
`isSuppressedByExpose` when the activated app is the Dock, fading the panel out over
0.12 s and back in over 0.25 s when anything else activates.
`NSWorkspace.activeSpaceDidChangeNotification` clears the suppression as a safety net
against getting stuck hidden.

**Known trade-off:** clicking a Dock icon or opening Launchpad also briefly fades the card,
because they are indistinguishable from Mission Control through this signal. This was
judged less jarring than the card hanging over Mission Control.

**Known limitation:** `activeSpaceDidChangeNotification` fires *after* the switch animation
completes, and macOS gives no notification when one *begins*. A direct desktop-to-desktop
switch that doesn't route through Mission Control (Ctrl+←/→) therefore cannot be pre-empted.
This is acceptable because the card is on all Spaces at a fixed position, so the outgoing
and incoming desktops show it in the same place — the same as per-desktop widgets.

Note that `activeSpaceDidChange` deliberately does **not** re-fade the card in. An earlier
version forced alpha to 0 and animated back up on arrival; because the notification is
post-animation, that read as a flicker on every desktop switch.

## Click-through

`AppSettings.clickThrough` maps to `panel.ignoresMouseEvents`. With it on, clicks pass to
whatever is beneath — which also means the card **cannot be dragged or resized**. Settings →
General shows an inline warning to this effect whenever the toggle is on.

## Trade-offs and constraints

- **Requires a running app.** Unlike a widget, the overlay only exists while Bibliada is
  running. That is the price of exact timing.
- **Not sandboxed.** The main app has `ENABLE_APP_SANDBOX: NO` because it places a window
  at desktop level and manages arbitrary frames. The widget extension *is* sandboxed.
- **Behaviors widgets get for free must be hand-coded** — grid snapping (not implemented),
  multi-display handling (via clamping), Spaces presence (via collection behavior).

## Things to know

- **The settings poll used to fight the drag.** `AppState.observeSettings()` originally
  called `applySettingsChange(_:)` unconditionally every 500 ms, which re-applied the
  *stored* `overlayFrame` to the panel. Since a continuous drag kept cancelling the 400 ms
  debounce, nothing was ever saved, and the poll yanked the window back — the card was
  effectively immovable. The fix has two halves, and **both** must hold:
  1. `observeSettings()` returns early when settings are unchanged, and passes
     `applyFrame:` only when `overlayFrame` itself differs from the previous tick.
  2. `applySettingsChange(_:applyFrame:)` additionally bails on
     `panel.isUserInteracting` or `panel.inLiveResize`.

  If you ever make the overlay apply geometry on a timer again, you will reintroduce this
  bug.
- **`OverlayPanel.isUserInteracting` spans the whole drag.** `isMovableByWindowBackground`
  drags run inside a nested event-tracking loop within `super.mouseDown(with:)`, which does
  not return until mouse-up. Main-queue work is still serviced during that loop, which is
  precisely why the flag is needed.
- **`spaceObservers` is `nonisolated(unsafe)`** so the non-main-actor-isolated `deinit` can
  unregister the notification observers. It is only mutated on the main actor during setup.
- **The card's own `opacity` setting is separate from the panel's `alphaValue`.**
  `VerseCardView` applies `AppSettings.opacity` internally; the panel's `alphaValue` is
  reserved for the Mission Control fade. Don't conflate them.

## Key files

| Path | Role |
|---|---|
| `App/OverlayWindowController.swift` | Panel configuration, frame persistence, Exposé fading, screen clamping, `OverlayPanel` subclass |
| `App/AppState.swift` | `applyOverlayState()` creates/shows/hides the controller; `observeSettings()` drives live updates |
| `App/SettingsView.swift` | Size & Position tab, click-through toggle |

## Related docs

- `overview.md` — how the overlay compares to the widget
- `settings.md` — the Size & Position and General tabs
