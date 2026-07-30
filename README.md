# Bibliada

A small macOS menu-bar app that shows a random Bible verse on a customizable
gradient card, in two display modes:

1. **Widget mode** — a real WidgetKit widget you add to the Desktop or
   Notification Center, in the system's fixed sizes (small/medium/large/
   extraLarge). Its refresh interval is **best-effort**: the widget's
   `TimelineProvider` requests a new entry at your chosen frequency (hourly,
   every 3/6/12 hours, or daily), but macOS decides when to actually honor
   that request out of a limited daily reload budget (roughly 40–70 reloads
   per day system-wide, shared across all your widgets). Hourly refresh is
   realistic; anything sub-hourly simply isn't offered because the system
   would not reliably grant it. See `SPEC.md` for the full rationale.
2. **Desktop overlay mode** — a borderless, resizable window pinned at
   desktop level, always behind your other windows. This is where "any
   custom size" and "exact update frequency" actually live: it's a plain
   app-driven timer, not subject to WidgetKit's reload budget, and it can be
   sized to an arbitrary rectangle rather than the widget's fixed sizes.

Bibliada does not attempt wallpaper-image compositing (it would break
dynamic/rotating wallpapers and require polling) or Lock Screen widgets (no
public API on macOS).

## Verse source

Verse text is the **World English Bible (WEB)**, a public-domain translation,
served by the free [bible-api.com](https://bible-api.com). Bibliada picks a
random reference from its bundled curated catalog (`Shared/Resources/verses.json`,
which already carries WEB text for every entry) and optionally refreshes the
text from `bible-api.com` over the network. If the network call fails or
times out (8s timeout, no more than one retry), Bibliada falls back to the
bundled text, so both the app and the widget always render something —
the widget in particular can render instantly with zero network access.

## Building

```
./build.sh              # xcodegen generate, Release build, offer to install to /Applications
./build.sh --debug       # Debug configuration instead of Release
./build.sh --no-install  # build only, skip the /Applications install step
```

This requires [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`) and Xcode 26 / macOS 15+ SDK. `build.sh` never
silently deletes an existing `/Applications/Bibliada.app` — it prints what it
will do and asks for confirmation before overwriting.

## Signing caveat: App Groups need a real Team ID

Bibliada's app and widget share settings through an App Group,
`group.com.bibliada.shared`. `DEVELOPMENT_TEAM` is read from the
`BIBLIADA_TEAM_ID` environment variable and is **empty by default**, so a
plain `./build.sh` on a fresh clone builds with ad-hoc code signing
(`CODE_SIGN_IDENTITY=-`) and no team.

Without a real Apple Developer Team ID:

- The `com.apple.security.application-groups` entitlement cannot actually be
  granted (that requires a matching provisioning profile), so
  `SettingsStore` detects the App Group container is unreachable and
  degrades to `UserDefaults.standard` — separately for the app and for the
  widget process.
- Practically: the **widget renders its own defaults**, not the theme,
  frequency, or layout you chose in the app's settings window, because the
  two processes can no longer see the same storage.
- The **desktop-overlay mode is unaffected and works fully unsigned** — it
  runs entirely inside the main app process, so it always sees whatever
  settings you picked, with no App Group involved.

To get full app↔widget settings sharing, set a real Team ID before building:

```
export BIBLIADA_TEAM_ID=ABCDE12345
./build.sh
```

## Adding the widget

After installing Bibliada.app (`./build.sh` or a manual copy to
`/Applications`), launch it once so macOS registers the widget extension,
then:

1. Right-click the Desktop (or open Notification Center) and choose
   **Edit Widgets…**.
2. Find **Bibliada** in the widget gallery.
3. Drag a size (small, medium, large, or extra large) onto the Desktop or
   Notification Center.

## Credits

Verse text: **World English Bible (WEB)**, public domain, served by
[bible-api.com](https://bible-api.com).
