#!/usr/bin/env python3
"""Generate Shared/Resources/canon.json — the canonical book/chapter/verse
skeleton every bundled translation shares.

Verse *counts* come from the union across all bundled translations: a
versification gap in one translation (WEB's Textus-Receptus-only omissions,
see docs/translation-json-schema.md) must not shrink the canon, or the pool
browser would refuse to offer a verse another translation does have.

Book display names are taken per-translation so the browser can label columns
in the translation the user is reading.

Usage: python3 scripts/generate_canon.py
"""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
TRANSLATIONS = ROOT / "Shared" / "Resources" / "Translations"
OUT = ROOT / "Shared" / "Resources" / "canon.json"


def main() -> None:
    order = {}
    testament = {}
    names = {}          # book id -> {translation id: name}
    chapters = {}       # book id -> {chapter: max verse}

    for path in sorted(TRANSLATIONS.glob("*.json")):
        doc = json.loads(path.read_text(encoding="utf-8"))
        tid = doc["id"]
        for book in doc["books"]:
            bid = book["id"]
            order.setdefault(bid, book["order"])
            testament.setdefault(bid, book["testament"])
            names.setdefault(bid, {})[tid] = book["name"]
        for entry in doc["verses"]:
            bid, ch, v = entry["book"], entry["chapter"], entry["verse"]
            per_book = chapters.setdefault(bid, {})
            if v > per_book.get(ch, 0):
                per_book[ch] = v

    books = []
    for bid in sorted(order, key=lambda b: order[b]):
        per_book = chapters.get(bid, {})
        counts = [per_book.get(ch, 0) for ch in range(1, max(per_book, default=0) + 1)]
        books.append({
            "id": bid,
            "order": order[bid],
            "testament": testament[bid],
            "names": names[bid],
            "verseCounts": counts,
        })

    OUT.write_text(json.dumps({"books": books}, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    total = sum(sum(b["verseCounts"]) for b in books)
    print(f"wrote {OUT.relative_to(ROOT)}: {len(books)} books, "
          f"{sum(len(b['verseCounts']) for b in books)} chapters, {total} verses")


if __name__ == "__main__":
    main()
