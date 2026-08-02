# Bibliada — Apple publishing checklist

Compiled 2026-08-01 against the tree at `8fdb7c1`, targeting **both** channels:

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

## 0. Critical path — nothing else can start until this clears

- [ ] **Enrol in the Apple Developer Program** ($99/yr). You have no membership,
      no certificates, and no App Store Connect access today. **This gates every
      certificate, every App ID, the App Group, and both channels.**

      **As an individual, you pay up front.** Apple splits this by enrolment
      type: *"Individuals and sole proprietors/single-person businesses can
      review the license agreement and purchase a membership at the time of
      enrolment,"* whereas *"Organizations can review the license agreement and
      purchase a membership once Apple Developer Support verifies the enrolment
      information."* So the individual order is: submit enrolment → agree to the
      licence → pay $99 → confirmation email → membership active. Enrolment via
      the Apple Developer app is an **auto-renewable annual subscription**.

      Expect confirmation within 24 h; past that, contact support with your
      Enrolment ID. Pay with your **own** credit card — Apple: *"If you're
      paying by credit card and enrolling as an individual, you must use your
      own credit card… If you do not, your enrolment will be delayed and you'll
      be asked for a copy of your government-issued photo identification."*

      Enrol under your **exact legal name** — Apple states that "using an alias,
      nickname, or company name as your first or last name will cause a delay in
      the approval of your enrolment." P.O. boxes are not accepted as an address.
      Apple does not publish per-step timelines; organisation enrolment
      additionally requires a D-U-N-S number and takes materially longer.
      Starting it *on* Aug 6 puts the schedule at risk — start it before.
- [ ] Sign the latest Program License Agreement as Account Holder. No app record
      can be created until this is signed.
- [ ] Record your 10-character Team ID → `export BIBLIADA_TEAM_ID=…`

---

## 1. Blockers — Developer ID / notarization

The current Release build is **unsigned**, and the project as written cannot
produce a signable one. Verified empirically against the existing artifact:
`flags=0x20002(adhoc,linker-signed)`, `TeamIdentifier=not set`,
`Sealed Resources=none`, empty entitlements. That single artifact trips four of
Apple's rejection reasons at once.

- [ ] **`CODE_SIGN_IDENTITY: "-"` is a project-wide base setting**
      (`project.yml:31`) with no per-configuration override. Even with a real
      Team ID, Release signs ad hoc, which Apple rejects. Scope it to `Debug`.
- [ ] **`build.sh:57-60` forces `CODE_SIGNING_ALLOWED=NO`** whenever
      `BIBLIADA_TEAM_ID` is unset — and that is the *default* path that also
      installs to `/Applications`. A forgotten `export` on release day exits `0`
      and prints `==> Built:`. Make the release lane hard-fail instead.
- [ ] **`ENABLE_HARDENED_RUNTIME: YES` is currently a silent no-op**
      (`project.yml:54,79`) — the runtime bit is absent from the signature
      because nothing is really signed. It will start working once signing is
      fixed; verify `flags=…(runtime)` afterwards.
- [ ] **`build.sh:63` runs `xcodebuild build`, never `archive` + `-exportArchive`.**
      Only the export step strips `get-task-allow` and applies a secure
      timestamp. Two further independent rejection reasons. `scripts/release.sh`
      now does this correctly.
- [ ] **Create certificates:** Developer ID Application (for the `.dmg`).
      Developer ID Installer only if you ship a `.pkg`. Export each to `.p12` and
      back it up — Developer ID private keys cannot be re-downloaded and the
      slots are limited.
- [ ] **Resolve the App Group identifier before the first notarized build** —
      see §3. Renaming it later orphans users' settings.

Two easy-to-get-wrong details: `spctl -a -vvv -t install` is for *installer
packages*; a `.app` needs `-t exec`. And **you cannot staple a ZIP** — ship a
stapled `.dmg` so the ticket travels offline.

---

## 2. Blockers — Mac App Store

Two of these fail at **upload**, before a human ever sees the app.

- [ ] **App Sandbox is off for the main app** — `project.yml:53`,
      `App/Bibliada.entitlements:5-6`. Mandatory for the store
      (Guideline 2.4.5(i)). The widget is already sandboxed.
- [ ] **`LSApplicationCategoryType` missing** from `App/Info.plist` →
      **ITMS-90242**, hard upload failure. Suggested:
      `public.app-category.lifestyle`.
- [ ] **No app icon exists** → **ITMS-90236**. `AppIcon.appiconset/Contents.json`
      declares 10 mac slots; the repo contains **zero `.png` files**.
      - The classic `.appiconset` is still accepted in Xcode 26 — Icon Composer
        is recommended, not mandatory.
      - macOS does **not** auto-generate from a single 1024 px source. Supply all
        ten: 16, 32 / 32, 64 / 128, 256 / 256, 512 / 512, 1024.
      - There is no separate 1024 marketing upload on macOS; the `512x512@2x`
        slot *is* the store icon, taken from the binary.
      - Stay on the appiconset for this launch: an alpha-channel rejection
        (ITMS-90717) specific to the Icon Composer path was open in 2025 and
        **[unverified]** as fixed.
- [ ] **`ITSAppUsesNonExemptEncryption`** — add `<false/>` to `App/Info.plist`.
      Not a blocker, but every upload otherwise sits in "Missing Compliance"
      until answered by hand. HTTPS via `URLSession` is exempt.
- [ ] Register App IDs `com.bibliada.Bibliada` and `com.bibliada.Bibliada.Widget`,
      both with the App Groups capability.
- [ ] Certificates: **Apple Distribution** for the `.app`, **3rd Party Mac
      Developer Installer** for the `.pkg`.
- [ ] Mac App Store provisioning profiles for **both** bundle IDs. A missing
      *widget* profile is the most common export failure for an app with an
      extension.

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

- [ ] **Use `$(TeamIdentifierPrefix)group.com.bibliada.shared` in both variants.**
      XcodeGen expands it at build time, so one spelling serves both channels and
      both builds share one container.
- [ ] Update `Shared/SettingsStore.swift:137` and `Shared/VerseCache.swift:15`.
- [ ] **[unverified]** that App Store ingestion accepts a Team-ID-prefixed group.
      Confirm on the first upload. If rejected, use the bare form for the store
      variant *and* add a first-launch migration reading whichever domain is
      populated — otherwise users moving between channels silently lose every
      setting and the cached verse.

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
- Grow `verses.json` beyond its current 178 entries — pure data, no new code
- Export the card as an image via `ImageRenderer`; the view already renders at
  arbitrary sizes, and this doubles as store screenshots
- Favourites/pinning

### 1.1.5 Religious content — the guideline you asked about

> "Inflammatory religious commentary or inaccurate or misleading quotations of
> religious texts."

Apple does not restrict religious apps. This guideline targets inflammatory
*commentary* and *inaccurate quotation*. Bibliada ships zero commentary — the
safest posture available — so the entire exposure is accuracy, and there are
three real defects:

- [ ] **`BibleAPIResponse.translation_id` is decoded but never checked**; the
      result is hard-coded to `"WEB"` regardless of what the server returned.
      This can label non-WEB text as WEB.
- [ ] **`minimumScaleFactor(0.5)` will silently truncate** a long verse in a
      small widget. A verse cut off with no indication *is* misleading
      quotation. Verify on device.
- [ ] **Stray unmatched closing quotes** in the catalog (Genesis 28:15,
      Exodus 14:14) — extraction artifacts. **[unverified]** whether other
      entries diverge from the WEB source; the full catalog was not diffed.

### 5.2.2 Third-party services — bible-api.com

Its terms permit your use (free, no commercial restriction, no attribution
required), but state a limit of **15 requests per 30 seconds** and "do not use
this API to download an entire bible."

- [ ] Your *runtime* usage is fine. The *catalog build* was not:
      `docs/verse-source.md` records 178 verses fetched "~1.5 s apart" ≈ 20 req/30 s.
      Regenerate `verses.json` from the upstream `bible_api` / `open-bibles`
      source data and amend that doc.
- [ ] Archive dated copies of the bible-api.com terms and the ebible.org
      copyright page into `docs/publishing/reference/` — 5.2.2 says authorization
      "must be provided upon request", and the terms are an unversioned paragraph
      on a hobby site that can change without notice.
- [ ] Add a circuit breaker: a permanent outage currently means two 8 s timeouts
      per refresh, forever.

### Intellectual property

The World English Bible is **confirmed public domain** ("That means that it is
not copyrighted" — ebible.org), explicitly including commercial use. Two
obligations attach:

- [ ] **"World English Bible" is a trademark of eBible.org** — keep it out of the
      app name, subtitle, and keywords. Descriptive credit in the description is
      nominative fair use and fine.
- [ ] Don't alter the text while still calling it WEB. `normalize()`'s whitespace
      collapsing is formatting and fine; fix the stray quotes.
- [ ] `NSHumanReadableCopyright` omits **your own** copyright, and the widget's
      Info.plist has no copyright key at all.
- [ ] **[unverified]** whether "Bibliada" collides with an existing App Store
      name or registered mark. Search before reserving.

---

## 5. Required artifacts — none of these exist today

- [ ] **Privacy policy at a stable public URL.** Guideline 5.1.1 applies to
      *all* apps — "if any" — so collecting nothing is not an exemption. It must
      also be linked **inside the app**; `SettingsView.swift` currently has no
      `Link`/`openURL` call anywhere.
- [ ] **Support URL** with a working contact method (Guideline 1.5). A public
      GitHub repo with Issues open qualifies.
- [ ] **LICENSE file.** Not an Apple requirement, but without one a public repo
      is all-rights-reserved by default.
- [ ] **Acknowledgements panel** (also the natural home for the privacy link),
      including a non-affiliation line to foreclose any 5.2.1 reading.
- [ ] **EULA** — for the store, leave Apple's standard LAEULA selected (no work).
- [ ] Screenshots: 1–10 at 1280×800 / 1440×900 / 2560×1600 / 2880×1800, 16:10,
      **no alpha channel**.
- [ ] Categories, age rating (answer the religious-content descriptor honestly),
      description, keywords, pricing (free, no IAP — nothing triggers §3).
- [ ] **EU DSA trader status** — mandatory to declare; apps without it are removed
      from the App Store in the EU. See the privacy note below before answering.

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

- [ ] Decide trader vs. non-trader. Selecting "not a trader" requires no contact
      info, but declares to EU consumers that consumer-protection rights don't
      apply to contracts with you. The DSA defines a trader broadly as acting
      "for purposes relating to trade, business, craft or profession" — a free
      hobby app is a plausible non-trader, but this is a legal call, not a
      technical one.
- [ ] **Your legal name will be the public seller name.** Apple: *"If you're an
      individual or sole proprietor/single-person business, your personal legal
      name will be listed as the seller on the App Store."* No alias is
      permitted. The only alternative is organisation enrolment under a legal
      entity, which requires a D-U-N-S number and takes materially longer — not
      viable on a five-day runway.

**None of this applies to the Developer ID channel** — no listing, no trader
disclosure, no seller name. Your name and Team ID are embedded in the signature
and readable via `codesign -dvvv`, but nothing is published.

**App Privacy questionnaire: "Data Not Collected"** is truthfully answerable —
no accounts, no identifiers, no analytics, no third-party SDKs. Any HTTPS request
does reveal the user's IP to bible-api.com's operator, but that is third-party
server logging, not developer collection; disclose it in the policy prose rather
than the questionnaire.

---

## 6. Code quality issues a reviewer would hit

- [ ] **`VerseProvider.swift:30-34` returns a blank card** (`reference: ""`,
      `text: ""`) if the bundled catalog fails to decode. `bundledRandom()` at
      `:46` has a John 3:16 fallback; `nextVerse()` doesn't. Mirror it — a blank
      card in front of a reviewer is a 2.1.
- [ ] **`BibliadaApp.swift:89` uses `NSApp.activate(ignoringOtherApps: true)`**,
      deprecated since macOS 14. The comment at `:83-87` claims it is "the
      reliable combination on macOS 15+"; it isn't — Sonoma moved to cooperative
      activation and menu-bar apps commonly get the window ordered in but not
      focused. Use `NSApplication.activate()` +
      `NSRunningApplication.yieldActivationToApplication(_:)`.

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

- [ ] **App Review notes** stating: this is a menu-bar app with no main window;
      click the book icon at the top-right after launch; to add the widget,
      right-click the desktop → Edit Widgets → Bibliada; the app works fully
      offline. This is a free-text field in App Store Connect and removes the
      failure mode outright.
- [ ] Consider opening the Settings window on first launch — a common pattern for
      menu-bar apps, and it helps real users, not just reviewers.
- [ ] **`VerseCache.swift:17-19` has no fallback guard** — `UserDefaults(suiteName:)`
      returns a usable object even when the domain is denied, and writes are
      silently dropped. Behaviour differs once sandboxed.
- [ ] **Submit a build signed with a real Team ID.** Per README, an unsigned
      build makes the widget render its own defaults and ignore every setting —
      a reviewer would file that as a functional bug.
- [ ] Verify TLS once: `nscurl --ats-diagnostics --verbose https://bible-api.com/John%203:16`.
      If it fails, fix the request — do **not** add an ATS exception, which turns
      a clean submission into one needing written justification.

### Confirmed clean

No private or undocumented API anywhere — zero matches for `@_silgen_name`,
`dlopen`, `NSSelectorFromString`, `SkyLight`, `CGSPrivate`, `AXUIElement`. The
desktop overlay, the likeliest place for window-server hacks, uses only public
`CGWindowLevelForKey(.desktopIconWindow)` (`OverlayWindowController.swift:91`).
HTTPS only, no ATS exceptions, no deprecated API beyond the activation call
above, no TODOs, no `print`/`NSLog`, no third-party SDKs.

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
in `VerseCache.swift:17` and `SettingsStore.swift:159`, there is no ITMS-91053
risk. A `PrivacyInfo.xcprivacy` is recommended for a clean Xcode privacy report,
not mandatory; reason codes `1C8F.1` + `CA92.1` if you add one.

---

## 7. Sequence

Enrolment is deliberately **not** happening before Aug 6. Both channels are
gated behind it — a Developer ID certificate requires the paid membership just as
the store does; a free Apple ID only yields personal-team development
certificates, which cannot be notarized. So nothing ships before Aug 6, and the
work below is split by what the membership actually gates.

### Decisions to settle first (no membership required)

1. **App Group form** (§3). Recommended: `$(TeamIdentifierPrefix)group.com.bibliada.shared`
   — the only form valid on both channels without a provisioning profile.
   Changing it after release orphans users' settings.
2. **Sandbox the Developer ID build too?** Not required. Recommended yes, so both
   channels behave identically and a store rejection can't surprise you with
   behaviour the direct build never exercised.
3. **Trader vs non-trader** for the EU, and whether to obtain a P.O. Box for the
   publicly displayed address (§5).
4. **Which 4.2 hedges, if any** (§4). Genuinely optional — no guideline text
   requires them.

### Before Aug 6 — needs no membership

Blocking, highest value first:

- **Regenerate `verses.json` from upstream `bible_api` / `open-bibles` source
  data.** Fixes three findings at once: the ToS rate-limit problem in how the
  catalogue was built, the stray unmatched quotes (a real 1.1.5 accuracy issue),
  and the 178-verse thinness behind the 4.2 concern.
- **App icon, all ten PNG sizes** — hard upload failure without it, and the item
  most likely to stall because it needs design work rather than code.
- **`App/Info.plist`:** `LSApplicationCategoryType` + `ITSAppUsesNonExemptEncryption`.
- **Privacy policy and support URL, hosted and live** — hosting has its own lead
  time, and both must resolve before submission.

Code fixes (§6): blank-card fallback, cooperative activation, `translation_id`
check, small-widget truncation test, `VerseCache` guard, Settings-on-first-launch.

Build restructuring (§1, §2) — writable now, *testable* only once certificates
exist: scope `CODE_SIGN_IDENTITY: "-"` to Debug, add the `ReleaseMAS` config and
the four entitlements variants, switch the App Group identifier, make `build.sh`'s
release path hard-fail instead of silently building unsigned.

Paperwork: LICENSE, acknowledgements panel with the non-affiliation line, archived
copies of the bible-api.com terms and ebible.org copyright page, draft App Review
notes, and a name/trademark check on "Bibliada" before reserving it.

> **Testing limitation:** local ad-hoc builds work fine, so every code fix above
> is verifiable now. The exception is **App Group settings sharing** — the
> entitlement cannot be granted without a real team, so the widget will keep
> showing its own defaults until enrolment. That is expected, not a regression.

### Aug 6, day 1 — enrol

Individual enrolment: agree to the licence, pay $99 with your own card,
confirmation within 24 h (§0). Then certificates, App IDs, App Group registration,
`export BIBLIADA_TEAM_ID`, and `./scripts/release.sh --skip-notarize` as a dry run
— full build and all signature checks with zero Apple round trips.

### Then — Developer ID first

Fewer blockers and no reviewer judgment: the notarization service either accepts
the signature or it doesn't. That yields a real distributable while store work
continues. Store readiness (sandboxed variants, icon in place, hosted URLs,
review notes) follows, then the first upload — budget for a second cycle, since
the first upload usually surfaces something. Notarization is fast (1–15 min per
submission, ~5–20 min per release for the two round trips); App Review is days.

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

Still to archive locally: the bible-api.com terms of use and the ebible.org
copyright page (§4).
