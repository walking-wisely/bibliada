---
name: verse-source
description: Where verses come from — a bundled 178-verse curated catalog of World English Bible text plus live fetches from bible-api.com, with offline fallback and a cross-process last-verse cache.
triggers: [verse, bible api, bible-api.com, catalog, verses.json, offline, WEB, world english bible, cache, translation]
related: [overview, widget]
---

# Verse source

Verses are public domain **World English Bible (WEB)** text, sourced from
[bible-api.com](https://bible-api.com) — no API key, no registration.

Two layers work together:

1. **A bundled curated catalog** (`Shared/Resources/verses.json`) — 178 verses with their
   full WEB text embedded. The app works entirely offline and renders instantly.
2. **A live fetch** from bible-api.com on each refresh, which re-pulls the text for a
   randomly chosen catalog reference.

## Why a curated catalog instead of a random endpoint

bible-api.com supports `?random=verse`, but truly random verses land on genealogies, census
lists, and fragments — the first test call returned Esther 8:3. So **selection** is driven by
the curated catalog (Psalms, Proverbs, Isaiah, the Gospels, Romans, Philippians and similar),
while **text** still comes from the API. This yields verse quality that's actually worth
displaying, without hand-transcribing any scripture.

Every string in `verses.json` was fetched from the API, not authored. The catalog was
regenerated on 2026-08-06 with `scripts/regenerate_verses.py`, which paces requests one every
2.5 s (~12 req/30 s) to stay under bible-api.com's published limit of 15 requests / 30 seconds
— the original build's ~1.5 s pacing (~20 req/30 s) exceeded it. The script re-fetches only
this fixed 178-reference list, never a bulk/whole-Bible pull. All 178 succeeded with no empty
entries and no duplicate references. Re-run it (and update this note) if the catalog is ever
regenerated again.

### The stray-quote defect and its fix

24 of the 178 verses came back from the API with an unmatched curly quote ("“" or "”") — not
a transcription mistake from the original throwaway script, but a property of bible-api.com
itself: it returns exactly one verse per request, and the WEB text renders direct speech with
quote marks that open or close *outside* that single verse's boundaries (the matching mark
sits in the verse before or after). Verified directly: a fresh, unmodified fetch of e.g.
Genesis 28:15 still returns the trailing `”` with no opening pair anywhere in that response.

Both the regeneration script (`balance_quotes()`) and the runtime normalizer
(`VerseProvider.normalize()` → `balanceQuotes()`) now strip exactly one dangling quote mark
per verse when the count of `“` and `”` doesn't match: the last `“` if the verse opens a
quotation that runs on, the first `”` if it closes one that started earlier. Nothing else in
the text is altered. This keeps the bundled catalog and any live re-fetch of the same
reference producing identical text.

Note that bible-api.com normalizes `Psalm` → `Psalms` in its response `reference` field. The
catalog stores the normalized form consistently, so a stored reference always matches what
would be displayed.

## Fetch behavior

`VerseProvider.nextVerse()` (an `actor`, in `Shared/VerseProvider.swift`):

1. Picks a random reference from `catalog`, avoiding the reference currently in `VerseCache`
   when the catalog has more than one entry — so consecutive refreshes don't repeat.
2. `GET https://bible-api.com/<percent-encoded reference>?translation=web`, 8 s timeout, at
   most one retry.
3. Normalizes the returned text: trimmed, with all whitespace and newline runs collapsed to
   single spaces.
4. On **any** failure, returns the bundled entry for that reference.
5. Always writes the result to `VerseCache`.

**It never throws.** A network failure degrades to bundled text rather than surfacing an
error state in the card.

`VerseProvider.bundledRandom()` is the synchronous, offline, network-free path — used for
widget placeholders and as the app's initial verse before the first async refresh completes.

Measured live: three sequential fetches completed in ~0.7 s total, with distinct references.

## Catalog loading

`VerseProvider.catalog` is decoded lazily from `verses.json` and cached behind an internal
lock-protected box.

It resolves the resource via `Bundle(for: BundleToken.self)` — **not** `Bundle.main`. The
same `Shared/` sources compile into both the app and the widget extension, and in an extension
`Bundle.main` is the *extension's* bundle. `Bundle(for:)` correctly finds each target's own
bundled copy. Verified present in both:
`Bibliada.app/Contents/Resources/verses.json` and
`Bibliada.app/Contents/PlugIns/BibliadaWidget.appex/Contents/Resources/verses.json`.

## The verse cache

`VerseCache` (`Shared/VerseCache.swift`) stores the last shown verse and its fetch timestamp
as `CachedVerse` in the same App Group container as settings, with the same
`UserDefaults.standard` fallback.

It serves three purposes:

- The app seeds its initial verse from it at launch, so the card is never empty on start.
- The widget's `snapshot` uses it, avoiding a network call.
- `AppState` uses `fetchedAt` to decide whether to refresh immediately on wake from sleep.

## Trade-offs

- **The catalog is fixed at build time.** Adding verses means regenerating `verses.json`; it
  is not fetched or updated at runtime.
- **One translation.** WEB only, because it is public domain. `Verse.translation` carries the
  string (`"WEB"`), so supporting more is a model-compatible extension, but the catalog and
  the fetch URL both currently hardcode WEB.
- **The API call is arguably redundant** given the catalog already contains the text. It's
  retained so the displayed text tracks the upstream source, and as the hook for future
  translations.

## Key files

| Path | Role |
|---|---|
| `Shared/VerseProvider.swift` | `nextVerse()`, `bundledRandom()`, `catalog`, the `BundleToken` trick |
| `Shared/VerseCache.swift` | `CachedVerse`, `load()`, `save(_:)` |
| `Shared/Verse.swift` | The `Verse` model (`reference`, `text`, `translation`) |
| `Shared/Resources/verses.json` | The 178-verse catalog, bundled into both targets |

## Things to know

- **Attribution.** WEB is public domain; bible-api.com should still be credited (it is, in
  `README.md`).
- **Be careful about request volume** if you change the refresh cadence defaults or add
  retries — this is a free public API with no contract. Current behavior is one request per
  refresh, minimum cadence 1 minute.

## Related docs

- `overview.md` — how the verse reaches the two display modes
- `widget.md` — placeholder/snapshot/timeline use of the catalog and cache
