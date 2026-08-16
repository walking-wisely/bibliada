# Bibliada — Apple publishing checklist

Compiled 2026-08-01 against the tree at `8fdb7c1`; updated 2026-08-16 to
reflect completed Apple Developer Program enrolment (§0) and the removal of
the live bible-api.com fetch in favor of three bundled offline translations
(§4/§6). Targets **both** channels:

- **Developer ID** — signed, notarized, stapled `.dmg` from your own site.
- **Mac App Store** — uploaded via App Store Connect.

The two are more different than they look. Notarization is *only* the Developer
ID path — for the Mac App Store, Apple notarizes during ingestion and you never
run `notarytool`. Conversely the App Store Review Guidelines bind *only* the
store build; nothing in them applies to your direct download.

Findings were produced by five parallel audits (signing, App Store/sandbox,
review guidelines, privacy, pipeline). Where an audit could not confirm a claim
from Apple's own documentation, it is marked **[unverified]** and should be
treated as a hypothesis to test, not a fact.

---

## 0. Critical path — cleared

- [x] **Enrol in the Apple Developer Program** ($99/yr). Membership is active.
- [x] Sign the latest Program License Agreement as Account Holder.
- [x] Record your 10-character Team ID → `export BIBLIADA_TEAM_ID=…`. Confirmed
      real (`8284H9W4YV`) and exercised through both the Developer ID and Mac App
      Store exports in §1/§2 below.

---

## 1. Blockers — Developer ID / notarization

The Release build **was** unsigned; this section is now cleared. Verified with
a real `BIBLIADA_TEAM_ID=8284H9W4YV`: `xcodebuild archive` +
`-exportArchive -exportOptionsPlist scripts/ExportOptions-developer-id.plist`
succeeded end to end, and the exported `Bibliada.app` shows
`Authority=Developer ID Application: Ivan Dutov (8284H9W4YV)` →
`Developer ID Certification Authority` → `Apple Root CA`,
`TeamIdentifier=8284H9W4YV`, `flags=0x10000(runtime)` — a real distribution
signature with hardened runtime actually on, not ad hoc.

- [x] **`CODE_SIGN_IDENTITY: "-"` is a project-wide base setting**
      (`project.yml:31`) with no per-configuration override. Even with a real
      Team ID, Release signs ad hoc, which Apple rejects. Scope it to `Debug`.
      Fixed in `7b1fbb7`; confirmed above via the Developer ID authority chain.
- [x] **`build.sh:57-60` forces `CODE_SIGNING_ALLOWED=NO`** whenever
      `BIBLIADA_TEAM_ID` is unset — and that is the *default* path that also
      installs to `/Applications`. A forgotten `export` on release day exits `0`
      and prints `==> Built:`. Make the release lane hard-fail instead.
      Already true: `build.sh` intentionally keeps this fallback as the fast
      local dev loop, but `scripts/release.sh:243` (`b79e291`) `die`s outright
      when `BIBLIADA_TEAM_ID` is unset — that's the actual release lane.
- [x] **`ENABLE_HARDENED_RUNTIME: YES` is currently a silent no-op**
      (`project.yml:54,79`) — the runtime bit is absent from the signature
      because nothing is really signed. It will start working once signing is
      fixed; verify `flags=…(runtime)` afterwards. Confirmed:
      `flags=0x10000(runtime)` on the signed export above.
- [x] **`build.sh:63` runs `xcodebuild build`, never `archive` + `-exportArchive`.**
      Only the export step strips `get-task-allow` and applies a secure
      timestamp. Two further independent rejection reasons. `scripts/release.sh`
      now does this correctly — confirmed by the successful `archive` +
      `-exportArchive` run above.
- [x] **Create certificates:** Developer ID Application (for the `.dmg`).
      Developer ID Installer only if you ship a `.pkg`. Export each to `.p12` and
      back it up — Developer ID private keys cannot be re-downloaded and the
      slots are limited. Both created via portal CSR upload, installed in the
      login keychain; CSRs/keys backed up at `~/Documents/BibliadaSigning/`
      (outside the repo).
- [x] **Resolve the App Group identifier before the first notarized build** —
      see §3. Renaming it later orphans users' settings. Done: Team-ID-prefixed
      form in both entitlements files, confirmed resolving correctly at sign
      time to `8284H9W4YV.group.com.bibliada.shared`.

Two easy-to-get-wrong details: `spctl -a -vvv -t install` is for *installer
packages*; a `.app` needs `-t exec`. And **you cannot staple a ZIP** — ship a
stapled `.dmg` so the ticket travels offline.

---

## 2. Blockers — Mac App Store

This section is also cleared. Verified with the same real Team ID:
`-exportArchive -exportOptionsPlist scripts/ExportOptions-app-store.plist`
succeeded and produced a signed `Bibliada.pkg` —
`pkgutil --check-signature` shows the chain
`3rd Party Mac Developer Installer: Ivan Dutov (8284H9W4YV)` →
`Apple Worldwide Developer Relations Certification Authority` →
`Apple Root CA`. Both `Bibliada.app` and the embedded
`BibliadaWidget.appex` signed and embed-validated cleanly during the same
export, which requires a working provisioning profile per bundle ID.

- [x] **App Sandbox is off for the main app** — `project.yml:53`,
      `App/Bibliada.entitlements:5-6`. Mandatory for the store
      (Guideline 2.4.5(i)). The widget is already sandboxed. Fixed in
      `7b1fbb7`; confirmed on in the entitlements dump during the export above.
- [x] **`LSApplicationCategoryType` missing** from `App/Info.plist` →
      **ITMS-90242**, hard upload failure. Suggested:
      `public.app-category.lifestyle`. Fixed in `7b1fbb7`.
- [x] **No app icon exists** → **ITMS-90236**. `AppIcon.appiconset/Contents.json`
      declares 10 mac slots; the repo contains **zero `.png` files**.
      - The classic `.appiconset` is still accepted in Xcode 26 — Icon Composer
        is recommended, not mandatory.
      - macOS does **not** auto-generate from a single 1024 px source. Supply all
        ten: 16, 32 / 32, 64 / 128, 256 / 256, 512 / 512, 1024.
      - There is no separate 1024 marketing upload on macOS; the `512x512@2x`
        slot *is* the store icon, taken from the binary.
      - Stay on the appiconset for this launch: an alpha-channel rejection
        (ITMS-90717) specific to the Icon Composer path was open in 2025 and
        **[unverified]** as fixed. All 10 slots present, generated in `7b1fbb7`.
- [x] **`ITSAppUsesNonExemptEncryption`** — add `<false/>` to `App/Info.plist`.
      Not a blocker, but every upload otherwise sits in "Missing Compliance"
      until answered by hand. HTTPS via `URLSession` is exempt.
- [x] Register App IDs `com.bibliada.Bibliada` and `com.bibliada.Bibliada.Widget`,
      both with the App Groups capability. Registered in the portal, both
      configured with the App Groups capability pointed at
      `group.com.bibliada.shared` ("Enabled App Groups (1)" on each, not just
      the checkbox — the checkbox alone doesn't associate the group).
- [x] Certificates: **Apple Distribution** for the `.app`, **3rd Party Mac
      Developer Installer** for the `.pkg`. Both created and installed;
      confirmed as valid `security find-identity -p basic` identities and
      exercised in the signed export/`.pkg` above.
- [x] Mac App Store provisioning profiles for **both** bundle IDs. A missing
      *widget* profile is the most common export failure for an app with an
      extension. Confirmed indirectly: the export above signs and
      embed-validates both `Bibliada.app` and `BibliadaWidget.appex`, which
      isn't possible without a valid profile for each. (The portal's Profiles
      page shows empty — expected: Xcode-managed automatic profiles don't
      surface there, only manually-created ones do.)

---

## 3. The App Group decision — make it once, now

An earlier draft of `PIPELINE.md` had this rule backwards; it has been
corrected, but the decision is still yours to make and it is hard to reverse.

| Form | Authorization | Developer ID | Mac App Store |
| --- | --- | --- | --- |
| `group.com.bibliada.shared` | portal registration **+ embedded provisioning profile** | conditional | conditional |
| `$(TeamIdentifierPrefix)group.com.bibliada.shared` | self-authorizing | ✅ | ✅ |

The Team-ID prefix is **not** a store-specific rule — it is the only form valid
on both channels without a profile authorizing it. Since macOS 15 Sequoia,
`~/Library/Group Containers` is SIP-protected and access requires one of: Mac App
Store delivery, a Team-ID prefix, or profile authorization. Your current
`xcodebuild build` path embeds no profile at all.

- [x] **Use `$(TeamIdentifierPrefix)group.com.bibliada.shared` in both variants.**
      XcodeGen expands it at build time, so one spelling serves both channels and
      both builds share one container. Done in
      `App/Bibliada.entitlements` and `Widget/BibliadaWidget.entitlements`.
- [x] Update `Shared/SettingsStore.swift` and `Shared/VerseCache.swift`. Since
      `$(TeamIdentifierPrefix)` is only expanded by Xcode inside entitlements
      files (not by Swift at runtime), both now resolve the suite name through
      a new `Shared/AppGroup.swift`, which reads the team identifier back from
      the running process's own code signature (`SecTaskCopyValueForEntitlement`)
      and falls back to the bare group name when unsigned.
- [x] ~~**[unverified]** that App Store ingestion accepts a Team-ID-prefixed group.~~
      **Confirmed.** Uploaded `Bibliada.pkg` (with the Team-ID-prefixed
      `8284H9W4YV.group.com.bibliada.shared` entitlement) to App Store Connect
      via `scripts/release.sh --variant app-store --upload`
      (`xcodebuild -exportArchive -exportOptionsPlist
      ExportOptions-app-store.plist ... destination=upload`). Both the
      "analysis" and "SPI analysis" ingestion stages accepted it
      ("Upload succeeded"), and TestFlight → macOS Builds shows Build 1 at
      status **Ready to Submit** — full server-side processing completed with
      no entitlement rejection. No fallback/migration needed; the
      Team-ID-prefixed form works unmodified on both channels.

---

## 4. App Review — content and policy (store build only)

### 4.2 Minimum Functionality — a discretionary risk, not a rule

Guideline 4.2 in full — this is the *entire* text:

> Your app should include features, content, and UI that elevate it beyond a
> repackaged website. If your app is not particularly useful, unique, or
> "app-like," it doesn't belong on the App Store. If your App doesn't provide
> some sort of lasting entertainment value or adequate utility, it may not be
> accepted. Apps that are simply a song or movie should be submitted to the
> iTunes Store. Apps that are simply a book or game guide should be submitted to
> the Apple Books Store.

**No clause prescribes any specific feature.** There is nothing about favourites,
sharing, clipboard, or a minimum amount of content. "Useful", "unique",
"app-like" and "adequate utility" are undefined and applied by reviewer
judgment. The sub-clauses are all inapplicable here: 4.2.1 is ARKit, 4.2.2 is
marketing material and link collections, 4.2.3 is standalone operation and
download disclosure, 4.2.6 is template services, 4.2.7 is remote desktop.

What can be stated factually: Bibliada is a native app with a real WidgetKit
extension and a custom overlay window (desktop-level ordering, click-through,
multi-display clamping), so the "repackaged website" and 4.2.2 framings do not
describe it. The narrower, concrete exposure is that `LSUIElement=true` means a
reviewer may launch the app, see *nothing*, and conclude it is broken.

**Required (addresses the concrete risk):**

- [ ] **App Review notes.** State that it is a menu-bar app with no main window,
      give literal widget-install steps, and state that it works fully offline.

**Optional hedges against the subjective call** — reasonable to decline, and
none is required by any guideline text:

- Copy verse to clipboard (most utility per hour of work)
- Grow the curated reference pool beyond its current translation-agnostic set
  (`Shared/Resources/curated-references.json`) — pure data, no new code. (The
  old flat `verses.json` of 178 WEB-only entries is gone; each translation's
  full ~31,000-verse corpus is already bundled, so this is now about widening
  *which* verses get selected, not adding more raw text.)
- Export the card as an image via `ImageRenderer`; the view already renders at
  arbitrary sizes, and this doubles as store screenshots
- Favourites/pinning

### 1.1.5 Religious content — the guideline you asked about

> "Inflammatory religious commentary or inaccurate or misleading quotations of
> religious texts."

Apple does not restrict religious apps. This guideline targets inflammatory
*commentary* and *inaccurate quotation*. Bibliada ships zero commentary — the
safest posture available — so the entire exposure is accuracy.

The verse pipeline was rearchitected since this was written (`818a060` onward,
finished in the `VerseProvider`/`TranslationCatalog` rewrite): there is no
longer a `bible-api.com` fetch anywhere. All three translations — **WEB**,
**KJV**, and **Kulish** (Ukrainian, 1871/1903) — are bundled full corpora
(`Shared/Resources/Translations/*.json`) resolved via a translation-agnostic
curated reference pool. `VerseProvider.nextVerse` never throws and never talks
to a server; see `docs/verse-source.md`. That removes the `translation_id`
mislabeling risk entirely — there is no server response to trust or distrust,
only a pure in-memory lookup keyed by the caller-selected translation ID — and
retires the whole §5.2.2 bible-api.com section below (obsolete, kept only for
history at the bottom of this section).

- [x] ~~`BibleAPIResponse.translation_id` decoded but never checked~~ — moot.
      `BibleAPIResponse`/the live fetch no longer exist; each translation's text
      is loaded from its own bundled JSON file, so the displayed `translation`
      is always the one that was actually resolved.
- [ ] **`minimumScaleFactor(0.5)` will silently truncate** a long verse in a
      small widget. A verse cut off with no indication *is* misleading
      quotation. Verify on device — unaffected by the network removal.
- [x] **Stray unmatched closing quotes** — fixed in `818a060`: corrected in the
      regenerated catalog and defensively in `VerseProvider.normalize()`, since
      the artifact could recur on any future re-fetch. **[unverified]** whether
      the full three-translation corpus (not just the original 178-verse WEB
      pool) has been diffed for other extraction artifacts, particularly in KJV
      and Kulish which went through separate conversions — see
      `docs/translation-json-schema.md` for how each was sourced.
- [x] ~~Add a circuit breaker for bible-api.com outages~~ — moot, no network
      call exists to time out. Note `App/Bibliada.entitlements` and
      `Widget/BibliadaWidget.entitlements` still carry
      `com.apple.security.network.client`; drop it now that nothing uses it, or
      the App Privacy questionnaire's "Data Not Collected" answer invites a
      reviewer to ask why network access is requested at all.

### Intellectual property

All three bundled translations are public domain:

- **WEB** — **confirmed public domain** ("That means that it is not
  copyrighted" — ebible.org), explicitly including commercial use.
- **KJV** — public domain in the US; carries a dormant, print-only,
  England-specific Crown copyright that doesn't apply to digital distribution
  (per `docs/verse-source.md`, sourced in `docs/translation-json-schema.md`).
- **Kulish** (Kulish–Puluj–Nechuy-Levytsky, 1871/1903) — public domain by age.

Obligations that attach regardless of which translation:

- [ ] **"World English Bible" is a trademark of eBible.org** — keep it out of the
      app name, subtitle, and keywords. Descriptive credit in the description is
      nominative fair use and fine. Extend the same caution to "King James
      Version"/"KJV" — check for an equivalent live trademark before finalizing
      store copy.
- [x] Don't alter the text while still calling it by its translation name.
      `normalize()`'s whitespace collapsing is formatting and fine; the stray
      quotes are fixed (see above).
- [ ] `NSHumanReadableCopyright` in `App/Info.plist` only credits the WEB text
      (`"Verse text: World English Bible (public domain), via bible-api.com."`)
      — stale on two counts: it omits **your own** copyright, and it still
      names bible-api.com after the network path was removed. Update to credit
      all three translations and drop the bible-api.com mention. The widget's
      `Info.plist` has no copyright key at all.
- [ ] **[unverified]** whether "Bibliada" collides with an existing App Store
      name or registered mark. Search before reserving.

### Retired — bible-api.com (kept for history only)

Everything below described the old live-fetch architecture and no longer
applies to the shipped app; the section is retained so a future reader
understands why the entitlement/copyright cleanup above exists.

- ~~Runtime usage was within the 15 req/30 s limit; the *catalog build* was
  not (~20 req/30 s) — fixed by regenerating from source in `818a060`.~~
- ~~Archive dated copies of the bible-api.com terms and the ebible.org
  copyright page~~ — no longer a live third-party dependency to protect
  against; the ebible.org copyright-page archive is still worth keeping for
  the WEB/attribution record, but bible-api.com's ToS are now irrelevant.

---

## 5. Required artifacts — none of these exist today

- [x] **Privacy policy at a stable public URL.** Guideline 5.1.1 applies to
      *all* apps — "if any" — so collecting nothing is not an exemption. It must
      also be linked **inside the app**; `SettingsView.swift` currently has no
      `Link`/`openURL` call anywhere. Hosted at
      `https://walking-wisely.github.io/bibliada/privacy-policy.html`
      (`docs/privacy-policy.html`) and now linked in-app from the new
      Settings → About tab (`App/SettingsView.swift`'s `AboutSettingsTab`).
- [x] **Support URL** with a working contact method (Guideline 1.5). A public
      GitHub repo with Issues open qualifies —
      `https://github.com/walking-wisely/bibliada/issues`, already linked from
      `docs/index.html` and now also from Settings → About in-app.
- [x] **LICENSE file.** Not an Apple requirement, but without one a public repo
      is all-rights-reserved by default. Added at the repo root, adapted from
      the `holy-blocker` license (permissive, attribution + "Jesus is King."
      acknowledgment required in any about page — satisfied by the new About
      tab).
- [x] **Acknowledgements panel** (also the natural home for the privacy link),
      including a non-affiliation line to foreclose any 5.2.1 reading. New
      Settings → About tab: privacy/support/source links, the non-affiliation
      line, a public-domain translations credit, and the LICENSE-mandated
      "Jesus is King." line — fully localized (en/uk) via `Loc`.
- [x] **EULA** — for the store, leave Apple's standard LAEULA selected (no work).
      Confirmed as the recommendation in `docs/publishing/store-listing-draft.md`
      §6 — nothing to draft, just leave Apple's default selected in App Store
      Connect.
- [ ] Screenshots: 1–10 at 1280×800 / 1440×900 / 2560×1600 / 2880×1800, 16:10,
      **no alpha channel**. Not done — needs a human at a real Mac with a
      running build. Shot list and a `screencapture`/`sips` capture recipe
      (including alpha-channel stripping) are drafted in
      `docs/publishing/store-listing-draft.md` §9.
- [ ] Categories, age rating (answer the religious-content descriptor honestly),
      description, keywords, pricing (free, no IAP — nothing triggers §3).
      Content drafted and ready to paste in
      `docs/publishing/store-listing-draft.md` §1–5 (description, keywords,
      category recommendation, age-rating guidance, pricing confirmation) —
      still needs to actually be entered into App Store Connect by hand.
- [x] **EU DSA trader status** — mandatory to declare; apps without it are removed
      from the App Store in the EU. See the privacy note below before answering.
      **Decided: non-trader** (free hobby app, no commercial activity) — see
      `docs/publishing/store-listing-draft.md` §7 for the justification and
      consequence (no EU contact info required on the product page).

### What becomes public, and how to limit it (store build only)

Two different addresses, with different rules — don't conflate them:

| | Enrolment address | DSA trader contact info |
| --- | --- | --- |
| Purpose | identity verification, billing | EU consumer disclosure (DSA Arts. 30–31) |
| P.O. Box allowed | **no** — real street address | **yes** — Apple's field is "Address or P.O. Box" |
| Published | no | **yes, on your EU product pages** |

For individuals the published trader fields are *"Address or P.O. Box, Phone
number, Email address."* Use a P.O. Box or virtual mailbox and dedicated
phone/email — your home address never has to appear.

- [x] Decide trader vs. non-trader. Selecting "not a trader" requires no contact
      info, but declares to EU consumers that consumer-protection rights don't
      apply to contracts with you. The DSA defines a trader broadly as acting
      "for purposes relating to trade, business, craft or profession" — a free
      hobby app is a plausible non-trader, but this is a legal call, not a
      technical one. **Decided: non-trader** — see
      `docs/publishing/store-listing-draft.md` §7.
- [ ] **Your legal name will be the public seller name.** Apple: *"If you're an
      individual or sole proprietor/single-person business, your personal legal
      name will be listed as the seller on the App Store."* No alias is
      permitted. The only alternative would have been organisation enrolment
      under a legal entity (D-U-N-S number, materially longer process) — moot
      now that individual enrolment is already complete (§0).

**None of this applies to the Developer ID channel** — no listing, no trader
disclosure, no seller name. Your name and Team ID are embedded in the signature
and readable via `codesign -dvvv`, but nothing is published.

**App Privacy questionnaire: "Data Not Collected"** is truthfully answerable —
no accounts, no identifiers, no analytics, no third-party SDKs, and — since the
bible-api.com fetch was removed — no network requests of any kind. The old
caveat about bible-api.com seeing the user's IP no longer applies; nothing
leaves the device.

---

## 6. Code quality issues a reviewer would hit

- [x] **Blank-card fallback** — moot as originally described. The
      `BibleAPIResponse`/decode-failure path that produced `reference: ""` no
      longer exists; `VerseProvider.nextVerse` now resolves purely in-memory
      against the bundled corpora and, per `docs/verse-source.md`, "never
      throws — there's no failure mode to guard against once there's no
      network call, only a hardcoded John 3:16 fallback if the bundled files
      were somehow entirely missing." Worth a quick read of that fallback path
      to confirm it's still wired the same way after the rewrite, but the
      original defect (a live-fetch decode failure surfacing a blank card) is
      gone by construction.
- [ ] **`NSApp.activate(ignoringOtherApps: true)`**, deprecated since macOS 14,
      is still used — it moved rather than got fixed in the AppKit-controller
      rewrite (`ba48631`/`c5d1a75`). Now at
      `App/MenuBarController.swift:59` and `App/SettingsWindowController.swift:92`.
      Sonoma moved to cooperative activation and menu-bar apps commonly get the
      window ordered in but not focused. Use `NSApplication.activate()` +
      `NSRunningApplication.yieldActivationToApplication(_:)` in both spots.

      This compounds the discovery problem below: a reviewer who finds the menu
      bar icon, clicks **Settings…**, and gets a window that opens behind
      everything else has now seen the app "do nothing" twice.

### The `LSUIElement` discovery problem

Launching `Bibliada.app` produces, visibly: a `book.closed` glyph among the menu
bar extras. No Dock icon, no window, no app menu (`App/Info.plist:25-26`,
`App/BibliadaApp.swift:16-24`). The verse preview, the desktop-overlay toggle and
Settings are all behind a click on that glyph, and the widget needs separate
manual steps (right-click desktop → Edit Widgets → Bibliada).

A reviewer who doesn't know where to look sees an app that launches and does
nothing → **2.1 App Completeness**. The menu bar on a review machine is usually
crowded, and on a notched MacBook extras can be pushed off-screen entirely.

- [x] **App Review notes** stating: this is a menu-bar app with no main window;
      click the book icon at the top-right after launch; to add the widget,
      right-click the desktop → Edit Widgets → Bibliada; the app works fully
      offline. This is a free-text field in App Store Connect and removes the
      failure mode outright. Drafted and ready to paste in
      `docs/publishing/store-listing-draft.md` §8.
- [x] Consider opening the Settings window on first launch — a common pattern for
      menu-bar apps, and it helps real users, not just reviewers. Implemented:
      `MenuBarController` checks a `hasLaunchedBefore` flag in
      `UserDefaults.standard` and, the first time only, opens
      `SettingsWindowController` straight to the new About tab instead of the
      default Appearance tab — verified on a clean `defaults delete
      com.bibliada.Bibliada` launch, and confirmed silent on the next one.
- [ ] **`VerseCache.swift:16` has no fallback guard** — `UserDefaults(suiteName:)
      ?? .standard` returns a usable object even when the domain is denied, and
      writes are silently dropped. `SettingsStore.swift:200` already added an
      `isUsable` check for the same problem; mirror it in `VerseCache`.
      Behaviour differs once sandboxed.
- [x] **Submit a build signed with a real Team ID.** No longer a blocker — real
      Team ID (`8284H9W4YV`) is enrolled and exercised through both export
      pipelines (§0–§2). Still worth a final on-device check that the widget
      reads live settings rather than its own defaults before submission.
- [x] ~~Verify TLS once: `nscurl --ats-diagnostics ... bible-api.com`~~ — moot,
      no network call exists anymore to run TLS diagnostics against.

### Confirmed clean

No private or undocumented API anywhere — zero matches for `@_silgen_name`,
`dlopen`, `NSSelectorFromString`, `SkyLight`, `CGSPrivate`, `AXUIElement`. The
desktop overlay, the likeliest place for window-server hacks, uses only public
`CGWindowLevelForKey(.desktopIconWindow)` (`OverlayWindowController.swift:91`).
No network calls at all (the bible-api.com fetch was removed), no ATS
exceptions, no deprecated API beyond the activation call above, no TODOs, no
`print`/`NSLog`, no third-party SDKs. The `com.apple.security.network.client`
entitlement is now vestigial — see the §4 note above.

**The sandbox question that mattered most is a pass:** desktop-level overlay
windows are fine under App Sandbox. No entitlement governs window levels or
`collectionBehavior` — the sandbox covers filesystem, IPC, network, and hardware,
and these are client-side properties of your own windows. Comparable apps ship
sandboxed on the store today. **[unverified]** in the weak sense that no Apple
document affirmatively states this; the conclusion rests on the absence of any
governing entitlement plus shipping precedent. `LSUIElement` menu-bar-only apps
are likewise accepted.

**Privacy manifests: out of scope for macOS.** Apple's text — "You need to
provide this information … on iOS, iPadOS, tvOS, visionOS, and watchOS" —
excludes macOS from the *required-reason API* rules. Despite UserDefaults usage
in `VerseCache.swift:15` and `SettingsStore.swift:157`, there is no ITMS-91053
risk. A `PrivacyInfo.xcprivacy` is recommended for a clean Xcode privacy report,
not mandatory; reason codes `1C8F.1` + `CA92.1` if you add one.

---

## 7. Sequence

Enrolment (§0) is done and both build pipelines (§1, §2) are verified working
end to end with a real Team ID. Nothing below is gated on membership anymore —
what remains is paperwork, a handful of code fixes, and the actual submissions.

### Decisions still open

1. **Trader vs non-trader** for the EU, and whether to obtain a P.O. Box for the
   publicly displayed address (§5).
2. **Which 4.2 hedges, if any** (§4). Genuinely optional — no guideline text
   requires them.
3. **Sandbox the Developer ID build too?** Not required. Recommended yes, so both
   channels behave identically and a store rejection can't surprise you with
   behaviour the direct build never exercised.

### Remaining work, highest value first

- **Privacy policy and support URL** — done. `docs/index.html` /
  `docs/privacy-policy.html` are hosted on GitHub Pages, and Settings → About
  (`App/SettingsView.swift`) now links both in-app, satisfying Guideline
  5.1.1's in-app-link requirement.
- **LICENSE file** — done, added at the repo root.
- **Acknowledgements panel** with the non-affiliation line — done, same
  Settings → About tab; also carries the LICENSE-mandated "Jesus is King."
  line and a translations credit.
- **Draft App Review notes** (§4/§6): done, ready to paste from
  `docs/publishing/store-listing-draft.md` §8.
- **Name/trademark check on "Bibliada"** before reserving it in App Store
  Connect, plus the "World English Bible" / "King James Version" trademark
  caution in store copy (§4). Still open — store-copy drafts in
  `store-listing-draft.md` already avoid the trademarked full names, but the
  name-collision search itself hasn't been done.
- **`NSHumanReadableCopyright`** in `App/Info.plist` — stale (still credits
  only WEB via bible-api.com); add the widget's missing copyright key too (§4).
- **Store listing assets**: description, keywords, category, and age-rating
  guidance drafted in `docs/publishing/store-listing-draft.md` (§1–4) — still
  needs to be entered into App Store Connect. Screenshots remain undone;
  §9 of the same file has the shot list and capture recipe for whenever
  someone is at a real Mac with the app running.

Code fixes (§6): cooperative activation in `MenuBarController` and
`SettingsWindowController`, `VerseCache` fallback guard, small-widget
truncation test, Settings-on-first-launch, drop the now-unused
`com.apple.security.network.client` entitlement.

### Then — Developer ID first

Fewer blockers and no reviewer judgment: the notarization service either accepts
the signature or it doesn't. That yields a real distributable while store work
continues. Store readiness (icon in place — done; hosted URLs — done; in-app
privacy link, acknowledgements panel, review notes — still open) follows, then
the first upload — budget for a second cycle, since the first upload usually
surfaces something. Notarization is fast (1–15 min per submission, ~5–20 min
per release for the two round trips); App Review is days.

---

## 8. Reference material

- `docs/publishing/reference/app-store-review-guidelines.md` — full verbatim
  text, fetched 2026-08-01, section numbering preserved.
- `docs/publishing/PIPELINE.md` — one-time setup, usage, and a debugging runbook.
- `scripts/release.sh` — archive → export → verify → notarize → staple → `.dmg` →
  notarize → staple → checksums. Preflight fails loudly on a missing cert, team
  ID, or credentials profile; on rejection it runs `notarytool log` automatically
  and prints the reason.
- `.github/workflows/release.yml` — the same on a macOS runner. The `app-store`
  job is gated behind `if: false` until §2 is resolved.

Still to archive locally: the ebible.org copyright page, for the WEB
attribution record (§4). The bible-api.com terms of use no longer need
archiving — that dependency was removed; see the "Retired" note in §4.
