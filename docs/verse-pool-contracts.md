---
name: verse-pool-contracts
description: The parallel-build contract for verse pools — which of the three tracks owns which file, the shared foundation types every track codes against (VersePool, VersePoolResolver, ReferenceParser, BibleCanon, VersePoolStore, LocalizedKeySet), and the rules that keep three concurrent branches merging cleanly.
triggers: [verse pool tracks, parallel build, file ownership, pool contract, track 1, track 2, track 3, merge, worktree]
related: [verse-pool-customization, translation-json-schema, settings]
status: active
---

# Verse pools: build contracts

Implementation companion to [verse-pool-customization.md](verse-pool-customization.md),
which is the design. This document exists because that design is being built by
three tracks working **concurrently on separate branches**, and concurrent work
only merges cleanly if ownership and interfaces are settled first.

Read the design doc for *what* is being built and why. Read this one before
touching a file.

## The shared foundation (already on `main`, do not redesign)

These files are committed and building. All three tracks code against them as
given. If a track needs a change here, it is a **contract change**: raise it
rather than editing unilaterally, because the other two tracks compiled against
the current shape.

| File | Provides |
|---|---|
| `Shared/BibleCanon.swift` | `CanonBook`, `BibleCanon.books/book(id:)/chapterCount/verseCount/contains/totalVerseCount`. Backed by generated `Shared/Resources/canon.json` (~22 KB, 66 books, 1,189 chapters). Enumerate scripture through this — never by decoding a 5 MB corpus. |
| `Shared/VersePool.swift` | `VerseRange`, `PoolRule`, `VersePool`, `VersePool.curated`, `VersePool.curatedID`. |
| `Shared/VersePoolResolver.swift` | `resolve(rules:)`, `count(rules:)`, `expand(_:)`, `missingReferences(in:rules:)`, `canonicalOrder(_:_:)`. |
| `Shared/ReferenceParser.swift` | `parse(_:)`, `parseOne(_:)`, `bookID(matching:)`, `completions(for:limit:)`, `displayString(for:translationID:)`, plus `ParsedReference` / `ReferenceParseFailure` / `ReferenceParseResult`. |
| `Shared/VersePoolStore.swift` | `@MainActor @Observable` store: `pools`, `allPools`, `pool(id:)`, `activePool(settings:)`, `add/update/delete/duplicate/append(rule:toPoolWithID:)`, `reload()`. App Group backed, same round-trip probe as `SettingsStore`. |
| `Shared/LocalizedKeySet.swift` | The protocol that lets a feature keep its UI strings in its own file. See [Strings](#strings). |
| `AppSettings.activePoolID` | `UUID?`, persisted through `StoredSettings` with `decodeIfPresent`. nil = curated. |
| `scripts/generate_canon.py` | Regenerates `canon.json` from the bundled translations. |
| `scripts/smoke/run.sh` + `pool-smoke.swift` | Compiles the pure-logic half of `Shared/` into a CLI and asserts parser/resolver behaviour. Seconds to run, no signing needed. |

### Facts worth knowing before you write code

- **Ranges, not verse lists.** A pool stores rules over ranges. Rules apply in
  order, later winning: `[+PSA, -PSA.137, +PSA.137.1]` is Psalms without Psalm
  137 except its first verse. Never expand a pool into stored references.
- **The wire form is the range key string** — `"PSA"`, `"PSA.23"`, `"ROM.8.28"`,
  `"ROM.8.28-39"`. `VerseRange` encodes as that single string, and `PoolRule`
  encodes as `{"range": "...", "exclude": true}` with `exclude` omitted when
  false. This is what makes an exported pool hand-editable; don't wrap it in
  anything chattier.
- **The canon is a union across translations.** Psalms has 2,464 verses in
  `BibleCanon` and 2,461 in KJV. A reference existing in the canon does *not*
  mean `TranslationCatalog.verse(reference:translationID:)` can resolve it —
  handle nil. This is deliberate: a gap in one translation must not shrink what
  the browser offers.
- **The curated pool is built, not stored.** `VersePool.curated` is derived from
  `curated-references.json` at access time and is never written to defaults. It
  has a fixed id (`VersePool.curatedID`) and `isBuiltIn == true`; `update` and
  `delete` refuse it.
- **Never ship an empty pool.** `VersePoolStore.activePool(settings:)` already
  falls back to curated when the active pool is missing or resolves to nothing.
  Selection code must go through it rather than reading `activePoolID` directly.

## Track ownership

A track **creates and edits only the files in its own row**. Touching another
track's file is what turns three clean merges into one bad afternoon.

### Track 1 — model surfacing, Verses tab, omnibar, rule table

Owns:

- `App/VersesSettingsTab.swift` *(new)*
- `App/PoolEditorWindowController.swift` *(new)*
- `App/PoolEditorView.swift` *(new)* — including the **extension points** below
- `App/ReferenceOmnibar.swift` *(new)*
- `App/PoolRuleTable.swift` *(new)*
- `Shared/PoolLoc.swift` *(new)* — its strings
- `App/SettingsView.swift` *(edit)* — the `SettingsTab` enum case, its icon,
  its title, and the `selectedTabView` switch arm. **Track 1 alone edits this
  file.**
- `Shared/Localization.swift` *(edit)* — only if a genuinely shared string is
  needed. Prefer `PoolLoc`.

Ships: a user who knows references can build any pool and select it.

### Track 2 — browser columns, search, in-context add/exclude, shuffle bag

Owns:

- `App/PoolBrowserView.swift` *(new)* — the Book/Chapter/Verse columns
- `App/PoolSearchView.swift` *(new)*
- `Shared/VerseSearch.swift` *(new)* — corpus full-text search
- `Shared/ShuffleBag.swift` *(new)*
- `Shared/PoolBrowserLoc.swift` *(new)*
- `Shared/VerseProvider.swift` *(edit)* — pool-aware selection + shuffle bag.
  **Track 2 alone edits this file.**
- `App/MenuBarController.swift`, `App/OverlayCardView.swift`,
  `App/OverlayWindowController.swift` *(edit)* — the context-menu commands.
  **Track 2 alone edits these.**

### Track 3 — import, export, document type, plain-text interchange

Owns:

- `Shared/PoolDocument.swift` *(new)* — the `.bibliadapool` file format,
  encode/decode, validation report
- `Shared/PoolTextFormat.swift` *(new)* — plain-text read/write over
  `ReferenceParser`
- `App/PoolImportExport.swift` *(new)* — save/open panels, error presentation
- `Shared/PoolIOLoc.swift` *(new)*
- `App/Info.plist` *(edit)* — `CFBundleDocumentTypes` / `UTExportedTypeDeclarations`.
  **Track 3 alone edits this file.**
- `project.yml` *(edit)* — only if the document type needs build settings.
  **Track 3 alone edits this file.**

### Nobody edits

`Shared/VersePool.swift`, `Shared/VersePoolResolver.swift`,
`Shared/ReferenceParser.swift`, `Shared/BibleCanon.swift`,
`Shared/VersePoolStore.swift`, `Shared/LocalizedKeySet.swift`,
`Shared/AppSettings.swift`, `Shared/SettingsStore.swift`,
`Shared/TranslationCatalog.swift`.

Two exceptions, and only these:

- Track 1 may **add** cases to `Loc` if a string is truly shared.
- Any track may **add** parser aliases to `ReferenceParser.aliases`, with a
  smoke-test case alongside. Nothing else in that file.

## Extension points

Tracks 2 and 3 have to appear inside Track 1's editor and tab without editing
Track 1's files. Track 1 therefore commits these seams **first**, as no-op
placeholders, before building anything else — the other tracks fill them in.

In `App/PoolEditorView.swift`:

```swift
/// Filled in by the browser/search track. Track 1 ships this returning
/// `EmptyView()`; the editor already lays out space for it.
@ViewBuilder
static func discoverySection(pool: Binding<VersePool>, translationID: String) -> some View

/// Called by the browser and search surfaces to add what the user selected.
/// Track 1 owns the implementation; other tracks only call it.
func addRules(_ ranges: [VerseRange], isExclusion: Bool)
```

In `App/VersesSettingsTab.swift`:

```swift
/// Filled in by the import/export track — the Import…/Export… buttons.
@ViewBuilder
static func interchangeControls(store: VersePoolStore, selection: Binding<UUID?>) -> some View
```

A placeholder returning `EmptyView()` is a complete and correct Track 1
deliverable for both. It keeps every branch compiling on its own.

## Strings {#strings}

`Loc` is one enum plus one table in one file — a guaranteed three-way conflict.
Swift can't add enum cases from another file, so each track declares **its own**
key set in **its own** file:

```swift
enum PoolLoc: String, LocalizedKeySet {
    case versesTabTitle
    case addReference

    static let table: [PoolLoc: [AppLanguage: String]] = [
        .versesTabTitle: [.en: "Verses", .uk: "Вірші"],
        .addReference: [.en: "Add reference", .uk: "Додати посилання"],
    ]
}
```

Look up exactly as before: `language.t(PoolLoc.versesTabTitle)`. `Loc` conforms
to the same protocol, so existing call sites are unchanged. **Every string ships
with both `.en` and `.uk`** — the app switches language live and a missing
Ukrainian string is a visible bug, not a to-do.

## Working rules

1. **Build before you claim done.** `env -u BIBLIADA_TEAM_ID ./build.sh --debug
   --no-install` — the env override matters on a machine with a team id but no
   certificate. `** BUILD SUCCEEDED **` or it isn't finished. See the
   `run-bibliada` skill.
2. **Run `scripts/smoke/run.sh`** if you touched anything the parser or resolver
   reaches, and add cases for behaviour you added.
3. **Branch per track**, off the shared-foundation commit, in its own worktree
   so three `xcodegen`/`xcodebuild` runs don't fight over `.build/` and a
   regenerated `Bibliada.xcodeproj`.
4. **New files need no project edit.** XcodeGen globs `App/`, `Shared/` and
   `Widget/` (see `project.yml`), so adding a Swift file is enough. Anything in
   `Shared/` is compiled into the widget extension too — keep AppKit and
   `@MainActor` UI out of it.
5. **Swift 6, strict concurrency complete.** `Sendable` conformance is not
   optional, and a stray `@MainActor` in `Shared/` will break the widget build.
6. **Match the house style.** Comments in this codebase explain *why*, at
   length, especially where a decision looks arbitrary. Follow that; don't
   narrate what the code already says.
