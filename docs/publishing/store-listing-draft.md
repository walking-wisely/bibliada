# Bibliada — App Store Connect listing draft

Ready-to-paste content for the store-listing/content items in
`CHECKLIST.md` §5 that are pure copy/decisions rather than code. Screenshots
(item 9) are the one exception — that section is a shot list and capture
recipe only; it cannot be completed by an agent without a running app on a
real Mac.

Sourced from `docs/overview.md`, `docs/widget.md`, `docs/desktop-overlay.md`,
`App/Info.plist`, and `docs/publishing/CHECKLIST.md` §4/§5 (in particular the
"World English Bible" trademark caution).

---

## 1. App description

App Store Connect → "Description" field (limit 4000 characters). Draft below
is ~1,000 characters, well under the limit, on purpose — short, scannable
marketing copy reads better than a wall of text for a small utility app.

```
Bibliada puts a quiet Bible verse on your Mac, all day, without asking anything of you.

It lives in your menu bar — no Dock icon, no clutter, no window until you want one. Click the book icon for a live preview of the current verse, or turn on the desktop overlay: a resizable, click-through card that sits on your desktop at any size you choose, refreshing on the exact schedule you set. Prefer something more hands-off? Add the Bibliada widget from the system widget gallery and let macOS refresh it in the background.

Every card is drawn from three complete, bundled translations — including the WEB and KJV texts (public domain) plus the Ukrainian Kulish translation (1871/1903) — so you can read in the language and voice that speaks to you. Choose your own gradient, typeface, card size, and refresh interval to match your desktop.

Bibliada works entirely offline. There's no account to create, no server it talks to, and nothing about you is collected, tracked, or shared — the verse text and your settings never leave your Mac. It's free, with no in-app purchases, no ads, and no subscriptions. Just Scripture on your desktop, exactly the way you set it up.
```

---

## 2. Keywords

App Store Connect → "Keywords" field (limit 100 characters, comma-separated,
no spaces needed after commas — Apple strips them). 98 characters:

```
bible,verse,scripture,daily verse,devotional,christian,menu bar,widget,offline,faith,KJV,WEB,quote
```

Notes:
- Deliberately excludes "World English Bible" and "King James Version" in
  full — see CHECKLIST.md §4's trademark caution. "KJV" and "WEB" as bare
  abbreviations are standard translation shorthand used generically across
  the App Store (many Bible apps list them) and are not the trademarked
  phrases themselves; this is a judgment call, not a certainty — drop them
  if you want zero exposure.
- "menu bar" and "widget" target the two features that differentiate this
  from a generic verse-of-the-day app.
- Not included: "Ukrainian" / "Kulish" — low expected search volume against
  the character budget; add it back if you want that audience specifically
  (would mean cutting something else, e.g. "quote").

---

## 3. Category

**Recommendation: keep `public.app-category.lifestyle` (already set in
`App/Info.plist`) → App Store Connect primary category "Lifestyle".**

Justification: Apple's "Reference" category on macOS skews toward
dictionaries, encyclopedias, and lookup/study tools — apps you consult for
information. Bibliada isn't a study tool (no search, no cross-references, no
commentary); it's an ambient, always-present desktop decoration that happens
to display a verse, the same positioning as a quote-of-the-day widget or a
desktop clock/weather app. That's squarely Lifestyle. Reference is a
plausible secondary category if App Store Connect offers a secondary-category
field for this listing — set it if available, but Lifestyle should stay
primary.

---

## 4. Age rating questionnaire

The relevant question in Apple's age-rating questionnaire is about
**"Religious/Cultural Content"** (unaltered, non-commentary religious text is
a separate, milder bucket than "Mature/Suggestive Themes").

**Recommended answer:** Bibliada displays unaltered public-domain Bible
verses with no added commentary, interpretation, or editorializing. Answer
the religious-content descriptor as the **mildest applicable tier**
("Infrequent/Mild" if Apple's form offers a frequency scale for this
category, or simply answer "Yes" to "does your app contain religious
content" while answering "No" to every other content category — violence,
mature/suggestive themes, horror, gambling, alcohol/drugs, profanity, etc.).

Every other question should be answered "None" / "No": no violence, no
sexual content, no profanity (KJV/WEB/Kulish text itself may contain archaic
words like "whore" or "damn" in a handful of verses — these are literal
scripture, not app-authored profanity, and Apple's own guidance treats
unaltered religious text as exempt from the profanity descriptor), no
gambling, no user-generated content, no unrestricted web access (the app
makes no network calls at all).

**Expected resulting overall rating: 4+.** This is the standard rating for
Bible-text apps with no other mature content, and is consistent with how
comparable scripture apps are rated today.

---

## 5. Pricing

Bibliada is free with no in-app purchases, subscriptions, or paid unlocks of
any kind, so nothing in Guideline 3 (Business/Payments) applies — select the
"Free" price tier and skip in-app purchase setup entirely.

---

## 6. EULA

Use Apple's standard license agreement (LAEULA) — leave the default selected
in App Store Connect; there is no custom EULA to draft, since the app makes
no unusual claims about data, liability, or licensing terms beyond Apple's
boilerplate.

---

## 7. EU DSA trader status

**Decision: Non-trader.**

Justification for the record: Bibliada is a free hobby project with no
in-app purchases, no advertising, no subscriptions, and no other commercial
activity — it is not built, offered, or maintained "for purposes relating to
trade, business, craft or profession" under the DSA's definition of a
trader, so declaring non-trader status in App Store Connect is accurate.

Consequence per `CHECKLIST.md` §5: because the app is declared non-trader,
**no EU contact information** (address/P.O. box, phone number, email) needs
to be published on the EU product page. (Note this is a separate field from
Apple's own enrollment address, which stays private regardless — see the
table in CHECKLIST.md §5.)

---

## 8. App Review notes

App Store Connect → "App Review" → "Notes" field (private, reviewer-only
free text). Paste as-is:

```
Bibliada is a menu-bar-only utility app (LSUIElement = true). It has no Dock icon, no main window, and no application menu — this is intentional, not a bug.

To see the app: after launch, look for a small book icon (SF Symbol "book.closed") among the menu bar extras at the top right of the screen. Click it to open a popover with a live preview of the current Bible verse card, a "New verse now" action, a "Show on desktop" toggle, and a "Settings…" item — all the app's functionality is reached from this one menu.

To test the desktop overlay: click "Show on desktop" in that menu (or enable it from Settings → General). A resizable card will appear on the desktop, below normal app windows and above the wallpaper/Finder icons.

To test the widget: right-click an empty area of the desktop, choose "Edit Widgets," and search for or scroll to "Bibliada" in the widget gallery. Add it in any size. The widget renders the same verse card as the menu bar preview and the desktop overlay.

The app works fully offline. It makes no network requests, requires no account or sign-in, and does not collect, transmit, or track any user data — all three bundled Bible translations (WEB, KJV, and the Ukrainian Kulish translation) are shipped inside the app bundle and resolved entirely on-device.
```

---

## 9. Screenshots

**Status: NOT DONE.** This requires a human at a real Mac with a signed,
running build of Bibliada — an agent has no display to capture from. What
follows is the shot list and capture recipe to execute by hand.

### Requirements recap (from CHECKLIST.md §5)

- 1–10 images.
- Accepted resolutions (16:10, pick one and stay consistent): 1280×800,
  1440×900, 2560×1600, or 2880×1800.
- **No alpha channel** — App Store Connect rejects PNGs with an alpha
  channel for this asset type.

### Shot list

1. **Menu bar icon + open popover** — the book-glyph menu bar icon visible
   in the menu bar, with the popover open showing the live verse preview,
   "New verse now," "Show on desktop," and "Settings…" items. This is the
   single most important shot — it answers the LSUIElement discovery problem
   for a browsing user the same way the review notes answer it for a
   reviewer.
2. **Desktop overlay on a sample desktop** — the resizable verse card
   showing on an attractive desktop background (pick a calm, uncluttered
   wallpaper so the card is legible), demonstrating the "any size, anywhere"
   pitch.
3. **Settings → Appearance tab** — theme/gradient picker, font, corner
   radius, opacity controls.
4. **Settings → Verse Changes tab** (refresh cadence / translation
   selection) — whichever tab in the current `SettingsView.swift` layout
   surfaces translation choice (WEB / KJV / Kulish) and refresh interval;
   confirm the exact tab name against the running app before captioning.
5. **The widget on the desktop** — a placed WidgetKit widget (try a medium
   or large size for legibility) shown in the desktop/Notification Center
   widget layout, distinct from shot 2 so viewers understand there are two
   independent display modes.

Five shots covers the story end-to-end (discover → overlay → customize →
translations → widget) and stays comfortably under the 10-image cap; add a
sixth (dark-mode Settings, or a second gradient theme) only if it adds new
information rather than repeating a shot already taken.

### Capture recipe

1. Set the display's resolution (System Settings → Displays) to exactly one
   of the accepted sizes before capturing, or scale afterward with `sips`.
2. For a specific screen region (menu bar + popover, or overlay card on
   desktop):
   ```sh
   screencapture -R x,y,w,h -x ~/Desktop/shot-01-menubar.png
   ```
   `-x` suppresses the capture sound; it does not by itself guarantee no
   alpha channel — verify per file (see step 4).
3. For a specific window (e.g. the Settings window, whose exact frame is
   easier to grab by window than by coordinates):
   ```sh
   screencapture -o -w -x ~/Desktop/shot-03-appearance.png
   ```
   Click the target window when the crosshair appears. `-o` omits the
   window shadow, which otherwise adds unwanted transparent padding around
   the image.
4. **Strip the alpha channel** on every file before uploading — do this even
   for captures that look opaque, since `screencapture` can still emit an
   alpha channel for window captures with rounded corners or drop shadows:
   ```sh
   sips -s format png --setProperty hasAlpha no shot-01-menubar.png
   ```
   Verify with:
   ```sh
   sips -g hasAlpha shot-01-menubar.png   # should print "hasAlpha: no"
   ```
5. Resize/crop to the exact target resolution if the raw capture doesn't
   already match one of the four accepted sizes:
   ```sh
   sips -z 800 1280 shot-01-menubar.png   # height width, for 1280x800
   ```
   Prefer capturing at the target resolution natively (step 1) over scaling
   after the fact — scaling a menu bar/UI screenshot tends to blur text.
6. Repeat for each shot in the list above, numbering files in upload order
   (`shot-01-…` through `shot-05-…`) so the App Store Connect gallery order
   matches the intended narrative.

Once captured, drag the finished PNGs into App Store Connect → App Store tab
→ macOS App → screenshots section, then re-check each in the preview pane —
Connect will reject on upload if alpha survived the `sips` pass.
