---
name: translation-json-schema
description: The bundled per-translation JSON schema (one self-contained file per translation, book id + name + canonical verse array) and the canonical 66-book id list every translation file must share.
triggers: [translation, verses.json, schema, WEB, KJV, Kulish, book id, USFM, bundled corpus]
related: [verse-source]
---

# Translation JSON schema

This is the contract for every bundled full-corpus translation file. It exists so
independent conversions (different translations, different source formats) land on
byte-identical structure without needing to compare notes mid-conversion.

## File shape

One JSON file per translation, fully self-contained — no shared/cross-file manifest,
no lookup index shipped alongside it (that's built in memory at runtime, later, when a
feature actually consumes it).

```json
{
  "id": "WEB",
  "language": "en",
  "license": "public-domain",
  "source": "https://github.com/seven1m/open-bibles",
  "books": [
    { "id": "GEN", "name": "Genesis", "order": 1, "testament": "OT" },
    { "id": "EXO", "name": "Exodus", "order": 2, "testament": "OT" }
  ],
  "verses": [
    { "book": "GEN", "chapter": 1, "verse": 1, "text": "In the beginning, God created the heavens and the earth." }
  ]
}
```

### Top-level fields

| Field | Type | Notes |
|---|---|---|
| `id` | string | Short translation code, uppercase (`WEB`, `KJV`, `KULISH`). This is what `Verse.translation` carries. |
| `language` | string | BCP-47-ish, lowercase (`en`, `uk`). |
| `license` | string | `public-domain`, or `public-domain-outside-england` for KJV. No non-public-domain translation goes through this pipeline yet. |
| `source` | string | Where the text was pulled from — enough for someone to re-derive or verify it later. |
| `books` | array | Exactly 66 entries, one per canonical book (see list below). This translation's own display names — not shared across files. |
| `verses` | array | Every verse in the translation, in canonical order (see below). |

### `books[]` entry

| Field | Type | Notes |
|---|---|---|
| `id` | string | One of the 66 canonical ids below. Same id set in every translation file, always. |
| `name` | string | This translation's own display name for the book, in its own language (e.g. `"Genesis"` in `web.json`, `"Буття"` in `kulish.json`). |
| `order` | int | 1–66, canonical reading order (Genesis first, Revelation last). Same for every translation. |
| `testament` | string | `"OT"` or `"NT"`. |

### `verses[]` entry

| Field | Type | Notes |
|---|---|---|
| `book` | string | A `books[].id`. |
| `chapter` | int | 1-based. |
| `verse` | int | 1-based. |
| `text` | string | Trimmed, internal whitespace/newline runs collapsed to single spaces — same normalization `VerseProvider.normalize()` already does today. No verse-number prefix, no footnote markers, no cross-reference markup. |

Verses must appear in canonical order: grouped by book (in `books[].order` order), then
ascending chapter, then ascending verse. No gaps, no duplicates. Array position doubles
as reading order — that's intentional, don't rely on a separate index field.

## The canonical 66 book ids

Standard USFM/Paratext 3-letter codes. Every translation file uses exactly this set,
exactly these ids, exactly this order — it's the join key that lets book identity survive
across translations even when the display name and language don't match.

```
OT (39, order 1–39):
GEN EXO LEV NUM DEU JOS JDG RUT 1SA 2SA 1KI 2KI 1CH 2CH EZR NEH EST
JOB PSA PRO ECC SNG ISA JER LAM EZK DAN HOS JOL AMO OBA JON MIC NAM
HAB ZEP HAG ZEC MAL

NT (27, order 40–66):
MAT MRK LUK JHN ACT ROM 1CO 2CO GAL EPH PHP COL 1TH 2TH 1TI 2TI TIT
PHM HEB JAS 1PE 2PE 1JN 2JN 3JN JUD REV
```

## Known per-translation risk: versification

Chapter/verse boundaries are not universally identical across translations and
traditions — Psalm numbering and a handful of OT chapter breaks are the usual trouble
spots (Septuagint- vs Masoretic-based numbering). WEB, KJV, and Kulish are all expected
to use the standard Protestant/Masoretic versification (matching each other verse-for-
verse), but each conversion should **spot-check** a few of the known-divergent
references (Psalm 3 heading placement, the Psalm 116/147 split points) against the
source rather than assume it silently. Note anything found in that translation's
`source` field or as a comment in the conversion script — don't silently renumber to
force alignment with another translation.

## Validation checklist (every conversion must satisfy before it's done)

- [ ] Exactly 66 entries in `books[]`, ids match the canonical list exactly (no typos,
      no reordering).
- [ ] Every `verses[].book` value is one of the 66 ids.
- [ ] `verses[]` is in canonical order (book order, then chapter, then verse) with no
      duplicate `(book, chapter, verse)` tuples and no gaps in verse numbering within a
      chapter.
- [ ] `text` is non-empty for every verse, trimmed, whitespace-collapsed.
- [ ] Total verse count is sane for the testament(s) included (~23,145 OT + ~7,957 NT ≈
      31,102 for a full Bible — flag anything meaningfully off that number).
- [ ] `id`, `language`, `license`, `source` are all filled in, not placeholders.

## Not in scope for this schema

- Any cross-file manifest (`translations.json`) listing available translations — deferred
  until there's a translation-picker feature to drive.
- Any curated "good verse" pool (`curated-references.json`) — deferred until there's a
  random-suggestion feature to drive; the existing 178-entry `Shared/Resources/verses.json`
  is not yet reshaped into this format.
- An in-memory lookup index — built at runtime, later, when something actually queries by
  reference; not part of the bundled data.

## Related docs

- `verse-source.md` — the current (pre-this-schema) bundled catalog and live-fetch design.
