---
name: verse-source
description: Where verses come from — three bundled full-Bible translations (WEB, KJV, Kulish) selected via a curated, translation-agnostic reference pool, entirely offline, with the enabled-translations set configurable in General settings.
triggers: [verse, translation, WEB, KJV, Kulish, curated, verses.json, curated-references.json, TranslationCatalog, offline, cache, enabledTranslationIDs]
related: [overview, widget, settings, translation-json-schema]
---

# Verse source

Verses come from three bundled, public-domain translations — see
`docs/translation-json-schema.md` for the file format and how each was sourced/converted:

- **WEB** (World English Bible) — `Shared/Resources/Translations/web.json`
- **KJV** (King James Version) — `Shared/Resources/Translations/kjv.json`
- **Kulish** (Kulish–Puluj–Nechuy-Levytsky, 1871/1903, Ukrainian) — `Shared/Resources/Translations/kulish.json`

Everything is bundled at build time. **There is no network call anywhere in verse
selection** — this used to live-fetch from bible-api.com on every refresh; that's gone (see
"Why the live fetch was removed" below).

## Two layers

1. **Full corpora** — each translation file holds every verse in that translation
   (~31,000), keyed by a shared canonical 66 book-id set so the same verse can be resolved
   across translations. This is what a future "browse/select individual verses" feature
   would read from directly.
2. **A curated reference pool** (`Shared/Resources/curated-references.json`) — a flat list
   of `"BOOKID.chapter.verse"` keys (e.g. `"GEN.1.1"`), translation- and language-agnostic,
   verified present in all three bundled translations. This is what random *selection*
   actually draws from.

The curated pool exists for the same reason it always has: truly random verses land on
genealogies, census lists, and fragments (bible-api.com's `?random=verse` once returned
Esther 8:3 on the first try). It was originally 178 English references hand-picked against
WEB; `scripts/generate_curated_references.py` converted those into translation-agnostic
keys and dropped any not present in all three bundled files, so the same pool now serves
every translation.

## Fetch behavior

`VerseProvider.nextVerse(enabledTranslations:)` (an `actor`, in `Shared/VerseProvider.swift`):

1. Picks a random translation from the caller-supplied `enabledTranslations` and a random
   reference from the curated pool, avoiding the reference currently in `VerseCache` when
   there's more than one candidate.
2. Resolves that reference against the chosen translation via `TranslationCatalog` — a
   pure in-memory lookup, no I/O beyond the one-time decode of that translation's JSON file.
3. Always writes the result to `VerseCache`.

**It never throws** — there's no failure mode to guard against once there's no network
call, only a hardcoded John 3:16 fallback if the bundled files were somehow entirely
missing.

`enabledTranslations` is supplied by the caller (`AppState`, the widget's
`VerseTimelineProvider`) as `Array(SettingsStore.shared.settings.enabledTranslationIDs)`
rather than read by `VerseProvider` itself: `VerseProvider` is an `actor`, not
`@MainActor`, and `SettingsStore` is `@MainActor`-isolated, so the settings read happens on
the caller's side of the actor hop. See `docs/settings.md` for `enabledTranslationIDs`.

`VerseProvider.bundledRandom(enabledTranslations:)` is the synchronous, offline path used
for widget placeholders, the app's initial verse before the first async refresh completes,
and the Appearance tab's style preview — all cases where settings either aren't known yet
or don't matter, so it defaults to `["WEB"]` when no list is supplied.

## Translation catalog loading

`TranslationCatalog` (`Shared/TranslationCatalog.swift`) decodes each translation's JSON
lazily, on first access to that specific translation, and caches it behind a lock-protected
box keyed by translation id — the same shape the old single-catalog `VerseProvider.catalog`
used, generalized to multiple files. It also builds, at first load, a `(book, chapter,
verse) → array index` lookup per translation so resolving a curated reference is O(1)
rather than a scan.

Resource lookup goes through `Bundle(for: BundleToken.self)` — **not** `Bundle.main` — for
the same reason as the old catalog: the same `Shared/` sources compile into both the app
and the widget extension, and in an extension `Bundle.main` is the *extension's* bundle.

## Which translations are active

`AppSettings.enabledTranslationIDs: Set<String>` (default: all three bundled translations)
is set from General settings via `TranslationPickerView` — see `docs/settings.md`. It's
never allowed to go empty; the picker itself enforces that, and `TranslationCatalog` falls
back to `["WEB"]` defensively if it ever somehow receives an empty list.

## Why the live fetch was removed

The old design fetched WEB text from bible-api.com on every refresh, even though the
bundled catalog already had the same text — the app's own docs called this out as
"arguably redundant" before it was removed. There's no drift in public-domain text that a
live re-fetch would ever catch, so it bought nothing except: a network dependency in a
widget that should be instant, bible-api.com's terms (rate limits, no bulk use, "must
provide authorization upon request"), and an outage/timeout path to handle. Bundling all
three translations in full removes that entire category of risk — see
`docs/translation-json-schema.md` for the sourcing/licensing story per translation.

## The verse cache

`VerseCache` (`Shared/VerseCache.swift`) stores the last shown verse and its fetch timestamp
as `CachedVerse` in the same App Group container as settings, with the same
`UserDefaults.standard` fallback. Unchanged from before: the app seeds its initial verse
from it at launch, the widget's `snapshot` uses it to avoid recomputation, and `AppState`
uses `fetchedAt` to decide whether to refresh on wake.

## Key files

| Path | Role |
|---|---|
| `Shared/VerseProvider.swift` | `nextVerse(enabledTranslations:)`, `bundledRandom(enabledTranslations:)`, `curatedVerses(translationID:)` |
| `Shared/TranslationCatalog.swift` | `TranslationDocument` decode/cache, `VerseReference`, curated-pool loading, verse resolution |
| `Shared/Translation.swift` | `TranslationDocument`/`TranslationBook`/`TranslationVerseEntry` models, `BundledTranslations` (hardcoded picker metadata) |
| `Shared/VerseCache.swift` | `CachedVerse`, `load()`, `save(_:)` |
| `Shared/Verse.swift` | The `Verse` model (`reference`, `text`, `translation`) — unchanged |
| `Shared/Resources/Translations/*.json` | The three full-corpus translation files |
| `Shared/Resources/curated-references.json` | The translation-agnostic curated reference pool |
| `scripts/generate_curated_references.py` | Regenerates the curated pool from the old 178-entry list + the three translation files |

## Things to know

- **Attribution.** All three translations are public domain; KJV carries a dormant,
  print-only, England-specific Crown copyright that doesn't apply to digital distribution
  (see `docs/translation-json-schema.md`).
- **The old `Shared/Resources/verses.json`** (178 WEB-only entries) is gone — replaced by
  the translation-agnostic curated pool + full corpora.
- **Book names are per-translation.** A verse's displayed `reference` string uses that
  translation's own book name (`books[].name`), so the same verse reads as "Genesis 1:1" in
  WEB/KJV and "Буття 1:1" in Kulish — never assume `reference` strings are comparable across
  translations.

## Related docs

- `translation-json-schema.md` — the bundled per-translation JSON format and how each was sourced
- `overview.md` — how the verse reaches the two display modes
- `widget.md` — placeholder/snapshot/timeline use of the catalog and cache
- `settings.md` — `enabledTranslationIDs` and the General tab picker
