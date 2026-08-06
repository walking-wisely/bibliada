#!/usr/bin/env python3
"""Regenerate Shared/Resources/verses.json from bible-api.com.

Re-fetches the WEB text for every reference already in the catalog, at a pace
comfortably under bible-api.com's published limit of 15 requests / 30 seconds
(https://bible-api.com — "do not use this API to download an entire bible").
This script only ever re-fetches the existing curated reference list (178
verses picked for readability/utility, not the whole Bible), and paces
requests at one every 2.5s (~12 req/30s, ~20% margin under the cap).

Also fixes the "stray unmatched quote" defect noted in
docs/publishing/CHECKLIST.md 1.1.5: bible-api.com returns exactly one verse
at a time, so a reference that is mid-quotation in its source chapter comes
back with an opening or closing curly quote that has no partner in that
verse's text. This is not a transcription bug — the API's own response
contains the stray mark (verified directly against bible-api.com) — so it
recurs on every fetch, not just the one that built the original catalog. Fix:
strip the single dangling curly quote (the last unmatched "“" if the verse
opens a quotation that runs on, or the first unmatched "”" if it closes one
that started earlier) rather than altering any other text.

Usage:
    python3 scripts/regenerate_verses.py [--out Shared/Resources/verses.json]

Requires only the standard library.
"""

import argparse
import json
import sys
import time
import urllib.parse
import urllib.request

API_BASE = "https://bible-api.com/"
REQUEST_PACING_SECONDS = 2.5  # ~12 req/30s, under the 15 req/30s published limit
REQUEST_TIMEOUT_SECONDS = 8


def normalize_whitespace(text):
    return " ".join(text.split())


def balance_quotes(text):
    """Strip a single dangling curly quote left over from single-verse extraction.

    Mirrors the fix applied in Shared/VerseProvider.swift's normalize(), so the
    bundled catalog and any live fetch produce identical text for the same verse.
    """
    opens = text.count("“")  # “
    closes = text.count("”")  # ”
    if opens == closes:
        return text
    if opens > closes:
        idx = text.rindex("“")
    else:
        idx = text.index("”")
    return text[:idx] + text[idx + 1:]


def fetch_verse(reference):
    url = API_BASE + urllib.parse.quote(reference) + "?translation=web"
    with urllib.request.urlopen(url, timeout=REQUEST_TIMEOUT_SECONDS) as resp:
        payload = json.load(resp)
    text = payload.get("text", "")
    if not text:
        raise ValueError(f"empty text returned for {reference!r}: {payload}")
    return normalize_whitespace(balance_quotes(text))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out",
        default="Shared/Resources/verses.json",
        help="Path to the catalog file to read references from and overwrite.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Fetch and report, but don't write the output file.",
    )
    args = parser.parse_args()

    with open(args.out, "r", encoding="utf-8") as f:
        catalog = json.load(f)

    references = [entry["reference"] for entry in catalog]
    if len(references) != len(set(references)):
        sys.exit("Refusing to run: duplicate references in the existing catalog.")

    results = []
    changed = []
    for i, reference in enumerate(references, start=1):
        old_text = next(e["text"] for e in catalog if e["reference"] == reference)
        try:
            new_text = fetch_verse(reference)
        except Exception as exc:  # noqa: BLE001 - report and abort, don't half-write
            sys.exit(f"Failed on {reference!r} ({i}/{len(references)}): {exc}")

        if new_text != old_text:
            changed.append(reference)
        results.append({"reference": reference, "text": new_text, "translation": "WEB"})

        print(f"[{i}/{len(references)}] {reference}", file=sys.stderr)
        if i < len(references):
            time.sleep(REQUEST_PACING_SECONDS)

    if len(results) != len(references):
        sys.exit("Refusing to write: result count doesn't match reference count.")
    if any(not r["text"] for r in results):
        sys.exit("Refusing to write: at least one verse came back empty.")

    print(f"\n{len(changed)} of {len(results)} verses changed text.", file=sys.stderr)
    for ref in changed:
        print(f"  changed: {ref}", file=sys.stderr)

    if args.dry_run:
        print("Dry run — not writing.", file=sys.stderr)
        return

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"Wrote {args.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
