#!/usr/bin/env python3
"""Generate Shared/Resources/curated-references.json from the old verses.json catalog.

The old Shared/Resources/verses.json is a 178-entry curated pool (English
references like "Genesis 1:1" + WEB text) hand-picked to avoid landing random
verse selection on genealogies, census lists, and other unsuitable passages.
That curation judgment is worth keeping, but its shape (English reference
strings + a single translation's text) doesn't fit the new multi-translation
bundle in Shared/Resources/Translations/{web,kjv,kulish}.json, each of which
follows the schema in docs/translation-json-schema.md (a canonical 66
book-id set, `books[]` + `verses[]` with `{book, chapter, verse, text}`).

This script re-expresses that same 178-entry curated pool as a flat JSON
array of canonical reference keys ("BOOKID.chapter.verse", e.g. "GEN.1.1"),
suitable for driving a random-suggestion feature against any of the three
bundled translations without re-shipping any translation's text.

What it does:
  1. Reads Shared/Resources/verses.json for the ordered list of 178
     `{reference, text, translation}` entries.
  2. Builds an English book-display-name -> canonical book-id map from
     Shared/Resources/Translations/web.json's own `books[]` array (WEB's
     display names match the old catalog's English references).
  3. Parses each old reference string (e.g. "Genesis 1:1", "1 Corinthians
     13:4", "Song of Solomon 2:1") into (book_id, chapter, verse) by
     stripping the trailing " <chapter>:<verse>" and matching the remainder
     against the book-name map.
  4. Validates that the resulting (book, chapter, verse) tuple actually
     exists in web.json, kjv.json, AND kulish.json's `verses[]` arrays --
     dropping (and reporting) any reference missing from one or more of the
     three translations (e.g. a WEB-only or TR-gap verse).
  5. Writes the surviving reference keys, in original catalog order, as a
     pretty-printed (2-space indent) JSON array of strings to
     Shared/Resources/curated-references.json -- matching the formatting
     convention used by Shared/Resources/verses.json.

This script does not modify verses.json or any Translations/*.json file; it
only reads them. Re-run it whenever the curated pool (verses.json) is
revised, to regenerate curated-references.json from the new pool.

Usage:
    python3 scripts/generate_curated_references.py \
        [--verses Shared/Resources/verses.json] \
        [--translations-dir Shared/Resources/Translations] \
        [--out Shared/Resources/curated-references.json]

Requires only the standard library.
"""

import argparse
import json
import re
import sys
from pathlib import Path

REFERENCE_PATTERN = re.compile(r"^(.+)\s+(\d+):(\d+)$")

TRANSLATION_FILES = ["web.json", "kjv.json", "kulish.json"]


def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def build_book_name_map(web_data):
    """Map WEB's own English book display names to canonical book ids."""
    return {book["name"]: book["id"] for book in web_data["books"]}


def parse_reference(reference, book_name_map):
    """Parse "Genesis 1:1" / "1 Corinthians 13:4" -> ("GEN", 1, 1)."""
    match = REFERENCE_PATTERN.match(reference)
    if not match:
        raise ValueError(f"reference {reference!r} doesn't match '<book> <ch>:<vs>'")
    book_name, chapter, verse = match.group(1), int(match.group(2)), int(match.group(3))
    book_id = book_name_map.get(book_name)
    if book_id is None:
        raise ValueError(f"reference {reference!r}: unknown book name {book_name!r}")
    return book_id, chapter, verse


def build_verse_sets(translations_dir):
    """Load each translation's verses.json and return {filename: set of (book, chapter, verse)}."""
    verse_sets = {}
    for filename in TRANSLATION_FILES:
        data = load_json(translations_dir / filename)
        verse_sets[filename] = {
            (v["book"], v["chapter"], v["verse"]) for v in data["verses"]
        }
    return verse_sets


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--verses",
        default="Shared/Resources/verses.json",
        help="Path to the old curated verses.json catalog to read references from.",
    )
    parser.add_argument(
        "--translations-dir",
        default="Shared/Resources/Translations",
        help="Directory containing web.json, kjv.json, kulish.json.",
    )
    parser.add_argument(
        "--out",
        default="Shared/Resources/curated-references.json",
        help="Path to write the resulting flat JSON array of reference keys.",
    )
    args = parser.parse_args()

    verses_path = Path(args.verses)
    translations_dir = Path(args.translations_dir)
    out_path = Path(args.out)

    catalog = load_json(verses_path)
    web_data = load_json(translations_dir / "web.json")
    book_name_map = build_book_name_map(web_data)
    verse_sets = build_verse_sets(translations_dir)

    kept = []
    dropped = []
    for entry in catalog:
        reference = entry["reference"]
        try:
            book_id, chapter, verse = parse_reference(reference, book_name_map)
        except ValueError as exc:
            dropped.append((reference, str(exc)))
            continue

        key = (book_id, chapter, verse)
        missing_from = [
            filename for filename in TRANSLATION_FILES if key not in verse_sets[filename]
        ]
        if missing_from:
            dropped.append(
                (reference, f"absent in {', '.join(missing_from)}")
            )
            continue

        kept.append(f"{book_id}.{chapter}.{verse}")

    print(f"Kept {len(kept)} of {len(catalog)} references.", file=sys.stderr)
    for reference, reason in dropped:
        print(f"  dropped: {reference} -- {reason}", file=sys.stderr)

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(kept, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"Wrote {out_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
