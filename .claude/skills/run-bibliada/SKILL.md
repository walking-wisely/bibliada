---
name: run-bibliada
description: Build and launch Bibliada (the macOS menu-bar app in this repo) to see a change working, or to smoke-test after any Swift edit. Use whenever asked to run/build/screenshot the app, and proactively after editing any .swift file under App/, Shared/, or Widget/ — don't wait to be asked.
---

# Building and running Bibliada

Bibliada is an `LSUIElement` macOS app (no Dock icon, no main window) plus a
WidgetKit extension. **After any Swift change, build it — don't just read the
diff and assume it compiles.** This project's history has repeatedly hit
build breaks that only a real build catches (stale `Loc` keys, tab-enum
mismatches, sizing regressions).

## Build

```sh
cd /Users/dutov/Life/Personal/bibliada
./build.sh --debug --no-install
```

- `--debug` is enough for a smoke test; skip `--no-install` only if you
  actually want it dropped into `/Applications`.
- Watch for `** BUILD SUCCEEDED **` at the end. Any compiler error means the
  task isn't done yet, regardless of how the source read.
- A full XcodeGen + build takes well under a minute; there's no reason to
  skip it.

## Launch

```sh
pkill -f "Bibliada.app/Contents/MacOS/Bibliada" 2>/dev/null   # kill any previous instance first
open /Users/dutov/Life/Personal/bibliada/.build/Build/Products/Debug/Bibliada.app
```

There is **no window to check for** — this is the whole point of the app.
Success looks like: the process is running (`ps aux | grep -i bibliada`) and
a small `book.closed` glyph exists in the menu bar.

## Actually seeing it (the hard part)

A plain `screencapture` of the full screen often looks like nothing changed —
the menu-bar icon is small, white/template-colored, and easy to miss against
a busy wallpaper or a crowded menu bar (this machine typically has a dozen+
menu-bar extras already). Don't conclude "it's not showing" from a quick
glance at a screenshot; check properly:

```sh
# Confirm the status item actually exists and get its exact position:
osascript -e '
tell application "System Events"
  tell process "Bibliada"
    set b to menu bar 2
    set mi to menu bar item 1 of b
    return {position of mi, size of mi}
  end tell
end tell'
```

The returned `position` is in **points**; screenshots from `screencapture`
are saved at native **pixel** resolution (2x on Retina). Multiply the point
coordinates by 2 (or by the display's backing scale factor) before cropping
a screenshot to check that region — getting this conversion wrong is the
most likely reason a manual visual check comes up empty when the icon is
actually there.

To open the popover / Settings window programmatically instead of clicking
by hand:

```sh
osascript -e '
tell application "System Events"
  tell process "Bibliada"
    click menu bar item 1 of menu bar 2
  end tell
end tell'
sleep 1
screencapture -x /tmp/bibliada-check.png
```

From the open popover, the accessibility tree's UI elements can be inspected
with `name of every UI element of window 1` and clicked by index — text
matching on button titles (e.g. `"Settings…"`) is unreliable due to the
ellipsis character.

## Testing first-launch-only behavior

Bibliada persists a `hasLaunchedBefore` flag (and its regular settings) in
`UserDefaults.standard`. This ad-hoc, unsigned local build has **no
entitlements actually embedded** — confirmed with `codesign -d
--entitlements - <path>.app`, which prints nothing even though
`App/Bibliada.entitlements` declares App Sandbox. Only the properly signed
Developer ID / Mac App Store export pipelines actually apply it. So the
running app reads/writes the plain, non-sandboxed path:
`~/Library/Preferences/com.bibliada.Bibliada.plist` — **not** the
sandboxed-container path.

`defaults read`/`delete com.bibliada.Bibliada` and `plutil` **auto-redirect
to the sandboxed-container path**
(`~/Library/Containers/com.bibliada.Bibliada/Data/Library/Preferences/`)
regardless of that, because this bundle ID was registered as
sandboxed-container-using by an earlier signed export (App Store Connect
upload). That container file is always empty for local ad-hoc runs. Editing
or reading it teaches you nothing about what the real running app sees —
this cost most of a debugging session before it was caught.

To actually clear the flag for a genuinely fresh-install test:

```sh
/usr/libexec/PlistBuddy -c "Delete :hasLaunchedBefore" ~/Library/Preferences/com.bibliada.Bibliada.plist
killall cfprefsd   # required: cfprefsd caches values in memory independent of
                    # what's on disk, so a plain file edit alone can leave a
                    # running/next-launched process still reading the stale
                    # cached value
```

Then launch as above. Relaunching again afterward (without repeating both
steps) exercises the "returning user" path — the app writes the flag back on
first launch, so a second launch will correctly find it already `true`.

## First-launch activation is real, working code — verify it properly

`SettingsWindowController.show()` temporarily switches activation policy to
`.regular` and calls **both** `NSApp.activate()` **and**
`NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])`
to bring the first-launch Settings window frontmost. Both calls are load-
bearing — `NSApp.activate()` alone was confirmed insufficient by direct
instrumentation (temporary logging of `NSApp.isActive`, which stayed `false`
a full second after the call); `NSRunningApplication`'s activation API is
what actually flips it.

If a "does it come to the front" check ever looks like it's failing again,
suspect the testing setup before the code:

1. Confirm you're launching the freshly built app, not a stale one — compare
   `.build/Build/Products/Debug/Bibliada.app/Contents/MacOS/Bibliada.debug.dylib`'s
   mtime against `git log -1`. A stale Xcode DerivedData build or an old
   `/Applications/Bibliada.app` install are the most likely reason "nothing
   happens" — check `ps aux | grep -i bibliada` for what's actually running
   and where from.
2. Confirm `hasLaunchedBefore` is genuinely absent using the PlistBuddy +
   `killall cfprefsd` procedure above, not `defaults delete`/`plutil` against
   the (wrong) container path.
3. Only then, if it still doesn't come forward, treat it as a real
   regression — check via Accessibility (`frontmost` process name, `isActive`
   is not directly queryable externally but frontmost-process-name is a
   reliable proxy) immediately after launch, and take a screenshot right
   away rather than after several more `osascript` calls, since other apps
   (e.g. Safari autoplaying media) can reclaim focus a few seconds later and
   make a real success look like a failure in a delayed screenshot.

## Cleanup

```sh
pkill -f "Bibliada.app/Contents/MacOS/Bibliada" 2>/dev/null
```

Kill the debug instance when done poking at it, so it doesn't linger in the
menu bar across unrelated work.
