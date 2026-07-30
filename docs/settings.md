---
name: settings
description: Every user-facing setting across the four Settings tabs (Appearance, Size & Position, Updates, General), plus the input UX rules — commit-on-Return numeric fields, paired hour/minute clamping, Form row layout constraints — and how settings are persisted and migrated.
triggers: [settings, preferences, font picker, gradient, color picker, refresh interval, text field, commit on return, migration, typeface]
related: [overview, desktop-overlay, widget]
---

# Settings

All settings live in one `AppSettings` value (`Shared/AppSettings.swift`), persisted by
`SettingsStore` and edited through a four-tab Settings window (`App/SettingsView.swift`).
Every change is written through immediately — there is no Save button.

## Appearance tab

| Control | Bound to | Range / options |
|---|---|---|
| Live preview | — | A real `VerseCardView` that updates as you drag |
| Presets | `theme` | 8 swatches: Indigo Dusk, Dawn Peach, Forest, Slate, Sand, Midnight, Ocean, Plum |
| Gradient start / end color | `theme.startColor`, `theme.endColor` | `ColorPicker` |
| Gradient angle | `theme.angle` | Slider 0–360°, step 1, plus an editable `AngleField` (0 = top→bottom) |
| Text color | `theme.textColor` | `ColorPicker` |
| **Font** | `font` | 4 system designs + all installed font families |
| Corner radius | `cornerRadius` | 0–40 |
| Opacity | `opacity` | 0.2–1.0 |
| Text size | `fontScale` | 0.6–2.0× |

The live preview's verse is held in `@State` and picked once when the tab appears. Calling
`VerseProvider.bundledRandom()` inline in `body` would reroll the verse on every slider drag
and color-picker move, since each settings tweak re-evaluates `body`.

Each of the 8 presets carries its own `textColor` chosen for contrast against that specific
gradient — the light presets (Sand, Dawn Peach) use dark text. A custom gradient does not
auto-adjust text color; that's the user's call via the text color picker.

### Font selection

`FontChoice` is either one of four system designs (`System Serif`, `System Sans`,
`System Rounded`, `System Mono`) or a specific installed family by name. The picker
(`FontPicker`) lists the system designs, a divider, then every family from
`NSFontManager.shared.availableFontFamilies` — roughly 190 entries, with private faces
(names beginning with `.`) filtered out. Each family row is drawn in its own typeface so the
menu is browsable.

Behavior worth knowing:

- **A chosen family applies to the reference line too**, so the card reads as one typeface.
  With a *system design*, the reference keeps a distinct rounded semibold small-caps
  treatment — that contrast is deliberate.
- **Unknown families degrade, they don't break.** `Font.custom(_:size:)` silently falls back
  to the system font, so a family that was uninstalled after being selected leaves a
  readable card rather than a blank one. Verified against a deliberately bogus family name.
- **The widget resolves families by name at render time.** Because the extension is
  sandboxed, a font installed for the current user only may not resolve there; system-wide
  fonts will. It falls back to the system font.
- The stored form is a plain string: `system:serif` etc. for designs, or the bare family
  name. Kept readable and forward-compatible on purpose.

## Size & Position tab

Applies to the desktop overlay only (widget sizes are system-controlled).

| Control | Bound to | Range |
|---|---|---|
| Width / Height | `overlayFrame.size` | 150–6000 pt |
| X / Y | `overlayFrame.origin` | −20000…20000 pt |
| Quick presets | `overlayFrame.size` | Square 360, Wide 640×280, Tall 320×520 |

The 150 pt minimum matches the overlay panel's own clamp, so a value the field accepts can't
be silently overridden by the window afterwards.

**Coordinate space:** X/Y are the card's **bottom-left corner** in AppKit screen points,
measured from the bottom-left of the main display — so **Y counts upward**, not down from the
top. Off-screen values are clamped to the nearest display.

Dragging or edge-resizing the overlay writes back into these fields. See
`desktop-overlay.md`.

## Updates tab

| Control | Bound to | Range |
|---|---|---|
| Hours | `refreshMinutes` (÷60) | 0–24, step 1 |
| Minutes | `refreshMinutes` (mod 60) | 0–59, step 5 |
| Quick presets | `refreshMinutes` | 15 min, 30 min, 1 h, 3 h, 12 h, 24 h |

`refreshMinutes` is the single source of truth for cadence, free-form from **1 minute to 24
hours**. The desktop overlay honors it exactly; the widget rounds it down to a deliverable
cadence and the tab footer says which one. See `widget.md`.

**Paired clamping:** the two fields clamp as a pair, because a zero total would busy-loop the
refresh timer. `setHours` / `setMinutes` both run the combined total through `clampTotal`,
so typing `0` into Minutes while Hours is `0` snaps to 1 minute.

## General tab

| Control | Bound to |
|---|---|
| Show verse on desktop | `overlayEnabled` |
| Click-through | `clickThrough` |
| Show verse reference | `showReference` |

Turning on click-through reveals an inline warning that the overlay can no longer be dragged
or resized. A second warning appears when `SettingsStore.isShared` is `false` (App Group
unavailable) — though see the known issue about that flag in `widget.md`.

## Input UX rules

Two conventions apply to every numeric field, and both exist to fix real bugs.

### Commit on Return or focus loss — never per keystroke

`FrameField` (Double), `IntField` (Int, with stepper arrows) and `AngleField` (degrees) all
hold the in-progress edit in local `@State` and only parse, clamp, and publish on `onSubmit`
or when focus is lost.

A `TextField(value:format:)` writes through on **every keystroke**, and any clamp then runs
on each intermediate value. Typing `340` into a field clamped to a 150 minimum went
`3` → `150` → `15` → `150`, which presented as "my last digit vanished and the old value came
back". The same mechanism also pushed half-typed values straight to the overlay.

`AngleField` **wraps rather than clamps** on commit — angle is circular, so `370` means 10°
rather than being capped at 360. The size, position, and hour/minute fields clamp, because
those ranges are genuinely bounded.

All three components adopt outside changes (a drag, a preset button, a slider, owner-side
clamping) via
`onChange(of: value)`, but **only when not focused**, so they never overwrite an in-progress
edit. `IntField`'s stepper arrows write through immediately, since a click is already a
complete edit. After commit, both re-read the published value rather than echoing what was
typed, so owner-side clamping (like the hour/minute pairing) is visible.

### One control per Form row

In a macOS `Form`, a row's **first child is hoisted into the label column**. An
`HStack { fieldA; fieldB }` therefore makes the whole of `fieldA` act as the row's label,
producing lopsided spacing and misaligned fields. Every numeric control is its own
`LabeledContent` row for this reason.

Relatedly: the label must be rendered **once**. Passing a title to both a surrounding `Text`
/ `LabeledContent` *and* the `TextField` itself draws it twice ("Width Width").

## Persistence and migration

`SettingsStore` (`@MainActor @Observable`) JSON-encodes `AppSettings` under the key
`appSettings` in `UserDefaults(suiteName: "group.com.bibliada.shared")`, falling back to
`UserDefaults.standard` when the App Group is unreachable.

A private `StoredSettings` type mirrors `AppSettings` for coding, because `CGRect` doesn't
round-trip cleanly through `Codable` — `overlayFrame` is stored as four `Double`s via
`CodableRect`.

`StoredSettings` has a hand-written `init(from:)` so schema changes don't silently reset the
user's settings:

- **`refreshMinutes`** — if absent, a legacy `frequency` enum string is read and converted
  (`hourly` → 60). Falls back to the default only if neither key is present.
- **`font`** — `decodeIfPresent`, defaulting to `.default` for blobs written before the font
  setting existed.

`encode(to:)` is written explicitly because `CodingKeys` carries the legacy `frequency` case
with no backing property, which blocks the synthesized encoder. **If you add a field, update
all four of** `StoredSettings`'s properties, `init(from:)`, `encode(to:)`, and the
`settings` computed property — plus `AppSettings.default`.

## Key files

| Path | Role |
|---|---|
| `App/SettingsView.swift` | All four tabs, `FrameField`, `IntField`, `AngleField`, `FontPicker`, `ThemeSwatchButton` |
| `Shared/AppSettings.swift` | `AppSettings`, `UpdateFrequency`, `FontChoice`, cadence helpers |
| `Shared/SettingsStore.swift` | Persistence, App Group fallback, migration |
| `Shared/GradientTheme.swift` | `GradientTheme`, `RGBAColor`, the 8 presets |

## Things to know

- **`AppSettings` must stay `Equatable`.** `AppState.observeSettings()` diffs whole values to
  decide whether to do any work at all; losing `Equatable` would break the 500 ms poll's
  early exit and reintroduce the overlay frame-fighting bug (`desktop-overlay.md`).
- **`UpdateFrequency` still exists** even though it's no longer the app's cadence setting —
  it's the coarse vocabulary for the widget (`widgetFrequency`) and the legacy decode path.
- **`fontScale` and `font` are independent.** `fontScale` multiplies the geometry-derived
  size; `font` picks the typeface.

## Related docs

- `desktop-overlay.md` — what the Size & Position values drive
- `widget.md` — how cadence and theme reach the widget
- `overview.md` — the menu bar surface
