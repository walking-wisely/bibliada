---
name: verse-pool-customization
description: Design for user-customizable verse pools with verse-level granularity — the include/exclude range model, the Verses settings tab and its standalone pool editor (reference omnibar, book/chapter/verse browser, full-text search), in-context add/exclude, import/export interchange, and the shuffle-bag selection change small pools force.
triggers: [verse pool, custom verses, verse selection, pool editor, reference parser, import pool, export pool, shuffle bag, curated references, granularity]
related: [verse-source, translation-json-schema, settings]
status: implemented
---

# Verse pool customization

**Status: built.** All three phases below are implemented on
`verse-pools-integration`. This document remains the design rationale; see
[verse-pool-contracts.md](verse-pool-contracts.md) for how the work was split
and which file owns what.

Today the app draws from `Shared/Resources/curated-references.json` — a fixed
178-reference pool, identical for every user. This document designs the path to
letting a user define their own pool at verse-level granularity, keep several
such pools, and share them.

## Why this is cheap

The data work is already done. `Shared/Resources/Translations/*.json` bundles
the **full corpus** — 66 books, 31,098 verses per translation, for WEB, KJV and
Kulish. `curated-references.json` is nothing more than a 178-entry filter on top
of it, and `TranslationCatalog.verse(reference:translationID:)` already resolves
an arbitrary `VerseReference` against any bundled translation.

So verse-level customization needs no new corpus, no network path, and no change
to `docs/translation-json-schema.md`. It is a storage-and-UI problem sitting on
top of machinery that already exists.

## Storage model

A pool is **not** a flat list of resolved verses. It is an ordered list of
include/exclude *rules* over canonical ranges:

```swift
/// A canonical range: whole book, whole chapter, or a verse span.
/// "PSA" | "PSA.23" | "ROM.8.28-39"
struct VerseRange: Codable, Hashable, Sendable {
    let book: String                  // canonical id, e.g. "ROM"
    let chapter: Int?                 // nil = whole book
    let verses: ClosedRange<Int>?     // nil = whole chapter
}

struct PoolRule: Codable, Hashable, Sendable {
    let range: VerseRange
    let isExclusion: Bool
}

struct VersePool: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var rules: [PoolRule]             // applied in order; later rules win
}
```

Three reasons ranges beat a resolved reference list:

- **Size.** "All of Psalms except Psalm 137" is 2 rules instead of 2,458 stored
  ids. Pools live in the App Group `UserDefaults` alongside the rest of
  `AppSettings` (see `SettingsStore`), where a few kilobytes is fine and a few
  hundred is not something to invite.
- **Legibility.** The export file stays readable and hand-editable, which is
  what makes sharing work in practice.
- **Translation independence.** Rules are expressed in canonical `BOOK.C.V`
  terms — the same join key every bundled translation already shares. A pool
  built in English resolves verbatim against Kulish. This falls out of the
  existing schema for free and should not be given up.

Resolution (`[PoolRule] -> [VerseReference]`) happens once, and the resolved
array is cached in the App Group next to `VerseCache` so the widget extension
never re-resolves rules on a timeline refresh.

The existing 178 references stay as a **built-in, read-only pool** — the default
for every user, and the offered starting point ("Duplicate curated") when
creating a new one.

## Where it lives

### Verses tab

A new `SettingsTab` case, `verses`, icon `book.closed`, placed between
**Appearance** and **Verse changes**: it governs *what* is shown, where the
Verse changes tab governs *when*. See `docs/settings.md` for the tab set it
joins.

The tab itself stays compact, matching the density of its neighbours:

- List of pools, one row each: name, resolved verse count, checkmark on the
  active one.
- `+` (new / duplicate curated), duplicate, delete.
- `Edit…`, `Import…`, `Export…`.

### The editor is its own window

`Edit…` opens a separate, resizable window — not an inline panel and not a
sheet over Settings. The Settings window is deliberately compact and
fixed-feeling (`SettingsWindowController`), while the editor needs roughly
900×560 for a three-column browser plus a results list. This split is the
standard macOS shape: Mail keeps its rule list in preferences and opens each
rule's conditions in its own window; Keyboard shortcuts and Font collections do
the same.

## Editor design: two input paths, one rule list

Both input surfaces write into the same rule table. Neither is a mode.

### 1. Reference omnibar — the fast path

A token field across the top of the editor, in the shape of Mail's `To:` field.
Type

```
Ps 23; Rom 8:28-39; Jn 3:16; Prov 3
```

press Return, and get four tokens. Requirements:

- Fuzzy book matching over canonical ids, full names, common English
  abbreviations, and the localized names each translation file already carries
  in its `books` array (`Пс`, `Ps`, `Psalm`, `PSA` all resolve to `PSA`).
- Autocomplete popover while typing.
- ⌘F focuses the field from anywhere in the editor.
- The same parser handles pasted text and plain-text import (below) — write it
  once, in `Shared/`, so the widget target can validate too.

For anyone who knows their references this single control is most of the
feature's value, and it is the only thing that makes entering fifty scattered
verses tolerable.

### 2. Book / chapter / verse browser — the discovery path

Three columns beneath the omnibar: **Book | Chapter | Verse**.

The verse column must show **the actual verse text**, truncated to one line,
next to each number. Picking bare verse numbers out of a list is the standard
failure mode of this UI — nobody remembers what Romans 8:31 says by number, so
a number-only column forces the user out to another app to do the real work.

- Multi-select with ⇧ and ⌘; ⌘A selects the whole chapter.
- `Add selection` and `Add whole chapter` buttons; the latter emits a
  chapter-level rule rather than N verse rules.
- Draw the columns from a small generated `canon.json` (book → per-chapter verse
  counts, on the order of 4 KB, produced by the same script pipeline as
  `curated-references.json`). Without it, rendering the chapter column means
  decoding a 5 MB corpus file, which is not an acceptable cost for drawing a
  list of numbers.

### 3. Full-text search

A third surface in the same window: search the bundled corpus, get a result
list, `Add all 43 results` or check individual hits.

31,098 verses are already on disk with no network dependency, so this is close
to free to build — and searching "fear not" or "love" is a genuinely better way
to assemble a themed pool than drilling chapter by chapter. It is what makes
verse-level granularity feel like a feature rather than a data-entry chore.

### The rule table

Bottom half of the window, the single source of truth:

| Reference | Verses | |
|---|---|---|
| Psalm 23 | 6 | Include |
| Romans 8:28–39 | 12 | Include |
| Psalm 137 | 9 | Exclude |

- ⌫ deletes a row.
- The trailing control flips a row between include and exclude in place.
- A live `1,204 verses` counter and a `Preview random` button that renders a
  real card drawn from the current pool.

## In-context add and exclude

The highest-leverage controls are not in the editor at all:

- Right-click the overlay card → **Add to pool ▸ [pool]** / **Exclude this
  verse**.
- Menu bar → **Add current verse to ▸ [pool]**.

This turns pool-building into something done while reading rather than a chore
someone sits down for, and "stop showing me this one" is the most-requested
control in apps of this shape. `Exclude this verse` writes a single-verse
exclusion rule into the active pool — which is the reason exclusions are in the
model at all.

## Import and export

**Native format** — `.bibliadapool`, JSON:

```json
{
  "name": "Morning readings",
  "createdWith": "Bibliada 1.2",
  "rules": [
    { "range": "PSA.23", "exclude": false },
    { "range": "ROM.8.28-39", "exclude": false },
    { "range": "PSA.137", "exclude": true }
  ]
}
```

Register the UTI and document type so a double-click imports. A
`bibliada://pool?…` URL scheme is only worth adding if share-by-link is wanted
later; it is not needed for the file path.

**Plain text must also import.** A `.txt`/`.md` file — or just the pasteboard —
holding one reference per line, run through the same parser as the omnibar.
This is how verse lists actually circulate: in chat messages and notes, not in
files with custom extensions. Offer a plain-text variant on export for the same
reason.

**Validate on import, and report.** Resolve every rule against each enabled
translation and surface gaps explicitly — "3 references aren't present in WEB"
— rather than dropping them silently. WEB's handful of Textus-Receptus-only
gaps are documented in `docs/translation-json-schema.md`; an import is exactly
where a user should learn about them.

## Guardrails

- **Never an empty pool.** If a pool resolves to nothing (bad import, all rules
  excluded), fall back to the curated pool and show an inline warning in the
  Verses tab. `TranslationCatalog.randomVerse` already contracts to always
  return something; this preserves that.
- **Warn on tiny pools.** Under roughly ten verses, note that repetition will be
  heavy.
- **Replace random-with-one-avoid.** `VerseProvider.nextVerse` currently picks
  randomly while avoiding only the previous reference. That is adequate for 178
  verses and visibly broken for 15: the same handful recur constantly. Small
  pools require a **shuffle bag** — exhaust the pool in a shuffled order before
  reshuffling — persisted in the App Group next to `VerseCache` so the app and
  the widget draw from one bag. This is a required part of the feature, not a
  refinement.

## Staging

1. **Model and fast path.** `VersePool`, rule resolution, resolved-pool cache,
   the Verses tab, the reference omnibar, the rule table, the verse counter,
   and the shuffle bag. Shippable on its own — a user who knows references can
   already build any pool.
2. **Discovery.** Browser columns (plus generated `canon.json`), full-text
   search, in-context add/exclude from the overlay and menu bar.
3. **Interchange.** `.bibliadapool` document type, plain-text import/export,
   import validation reporting.
