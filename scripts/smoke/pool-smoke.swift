import Foundation

// Smoke checks for the pure-logic half of the verse-pool layer: the reference
// parser, range expansion, rule resolution, and the wire form. Run with
// scripts/smoke/run.sh. Add a case here whenever you teach the parser a new
// form — it is far cheaper than launching the app to find out.
//
// Verse counts come from BibleCanon, which is the *union* across bundled
// translations, so they can sit slightly above any single translation's count
// (Psalms is 2464 here, 2461 in KJV). That is deliberate — see BibleCanon.
func check(_ input: String, _ expected: String) {
    let r = ReferenceParser.parse(input)
    let got = r.references.map(\.range.key).joined(separator: "|")
        + (r.failures.isEmpty ? "" : " FAIL:" + r.failures.map(\.source).joined(separator: ","))
    print(got == expected ? "ok   \(input) -> \(got)" : "FAIL \(input) -> \(got)  (expected \(expected))")
}
print("canon books:", BibleCanon.books.count, "total verses:", BibleCanon.totalVerseCount)
check("Ps 23", "PSA.23")
check("Psalm 23:1-6", "PSA.23.1-6")
check("Rom 8:28-39", "ROM.8.28-39")
check("1 Cor 13", "1CO.13")
check("1Cor13:4-7", "1CO.13.4-7")
check("Ps 23; Rom 8:28-39; Jn 3:16", "PSA.23|ROM.8.28-39|JHN.3.16")
check("Rom 8:28, 31", "ROM.8.28|ROM.8.31")
check("PSA.23.1", "PSA.23.1")
check("Proverbs", "PRO")
check("Пс 23", "PSA.23")
check("Rom 8:28-99", "ROM.8.28-39")
check("Blurble 3:1", " FAIL:Blurble 3:1")
check("Phil 4:13", "PHP.4.13")
check("Jas 1:2-4", "JAS.1.2-4")
check("Mt 5:3\n2 Tim 1:7", "MAT.5.3|2TI.1.7")
check("Rom 99:1", " FAIL:Rom 99:1")
print("expand PSA.23 ->", VersePoolResolver.expand(VerseRange(key: "PSA.23")!).count, "(expect 6)")
print("expand PSA ->", VersePoolResolver.expand(VerseRange(key: "PSA")!).count, "(expect 2464 — union canon)")
let rules = [PoolRule(range: VerseRange(key: "PSA")!),
             PoolRule(range: VerseRange(key: "PSA.137")!, isExclusion: true),
             PoolRule(range: VerseRange(key: "PSA.137.1")!)]
print("resolve psalms-minus-137-plus-1 ->", VersePoolResolver.count(rules: rules), "(expect 2464 - 9 + 1 = 2456)")
let enc = try! JSONEncoder().encode(rules)
print("wire:", String(data: enc, encoding: .utf8)!)
print("roundtrip:", (try! JSONDecoder().decode([PoolRule].self, from: enc)).map(\.range.key))

// Shuffle bag: exhausts a small pool before any reference repeats, then
// reshuffles once exhausted, and resets when the resolved set changes even
// under the same pool id (a rule edit, not just a pool switch).
do {
    let refs = (1...5).map { VerseReference(book: "PSA", chapter: 23, verse: $0) }
    let pool = VersePool(name: "Shuffle test", rules: [PoolRule(range: VerseRange(key: "PSA.23.1-5")!)])

    var state: ShuffleBagState?
    var drawn: [String] = []
    for _ in 0..<5 {
        guard let (reference, next) = ShuffleBag.advance(state, pool: pool, resolved: refs) else {
            print("FAIL shuffle bag: advance returned nil mid-pass")
            break
        }
        drawn.append(reference.key)
        state = next
    }
    let allFiveSeen = Set(drawn) == Set(refs.map(\.key))
    print(allFiveSeen ? "ok   shuffle bag dealt all 5 references with no repeat" : "FAIL shuffle bag pass 1 -> \(drawn)")

    // The bag is now empty; the next draw must reshuffle rather than fail.
    if let (reference, reshuffled) = ShuffleBag.advance(state, pool: pool, resolved: refs) {
        print("ok   shuffle bag reshuffled after exhausting -> drew \(reference.key), \(reshuffled.remaining.count) left")
        state = reshuffled
    } else {
        print("FAIL shuffle bag: did not reshuffle after exhausting")
    }

    // Same pool id, different resolved contents (as if a rule changed):
    // the fingerprint must differ, so the bag rebuilds around the new set
    // instead of carrying over keys that may no longer even be in the pool.
    let editedRefs = Array(refs.prefix(2))
    if let (reference, resetState) = ShuffleBag.advance(state, pool: pool, resolved: editedRefs) {
        let expectedRemaining = editedRefs.count - 1
        print(
            resetState.remaining.count == expectedRemaining && editedRefs.map(\.key).contains(reference.key)
                ? "ok   shuffle bag reset when rules changed under the same pool id"
                : "FAIL shuffle bag did not reset on rule change -> remaining \(resetState.remaining)"
        )
    } else {
        print("FAIL shuffle bag: advance returned nil after rule change")
    }
}

// Full-text search: offline, case/diacritic-insensitive, results in
// canonical book/chapter/verse order.
do {
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        // "Fear not" is KJV phrasing; WEB says "don't be afraid" for the same
        // verses, so this checks WEB's own wording (and, via the all-caps
        // query, that matching is case-insensitive).
        let hits = await VerseSearch.shared.search("DON’T BE AFRAID", translationID: "WEB")
        print(hits.isEmpty ? "FAIL search \"DON’T BE AFRAID\" -> no hits" : "ok   search \"DON’T BE AFRAID\" -> \(hits.count) hits")

        let references = hits.map(\.reference)
        let inOrder = references == references.sorted(by: VersePoolResolver.canonicalOrder)
        print(inOrder ? "ok   search results are in canonical order" : "FAIL search results out of canonical order")

        let empty = await VerseSearch.shared.search("   ", translationID: "WEB")
        print(empty.isEmpty ? "ok   blank query returns no hits" : "FAIL blank query returned \(empty.count) hits")

        semaphore.signal()
    }
    semaphore.wait()
}
// MARK: - PoolDocument (.bibliadapool) round trip and validation

// The design doc's own example, byte-checked field by field rather than as a
// raw string compare (key order isn't part of the contract, just readability).
let sampleRules = [
    PoolRule(range: VerseRange(key: "PSA.23")!),
    PoolRule(range: VerseRange(key: "ROM.8.28-39")!),
    PoolRule(range: VerseRange(key: "PSA.137")!, isExclusion: true),
]
let sampleDoc = PoolDocument(name: "Morning readings", rules: sampleRules, createdWith: "Bibliada 1.2")
let sampleData = try! sampleDoc.encoded()
print("bibliadapool sample:\n" + String(data: sampleData, encoding: .utf8)!)
let roundtrippedDoc = try! PoolDocument.decode(from: sampleData)
// `PoolRule.id` is deliberately absent from the wire form (see
// Shared/VersePool.swift) and gets a fresh UUID on every decode, so a
// roundtrip compares name/createdWith/range-and-exclusion rather than full
// equality, which would spuriously fail on `id` alone.
let roundtripMatches = roundtrippedDoc.name == sampleDoc.name
    && roundtrippedDoc.createdWith == sampleDoc.createdWith
    && roundtrippedDoc.rules.map { ($0.range.key, $0.isExclusion) }.elementsEqual(sampleDoc.rules.map { ($0.range.key, $0.isExclusion) }, by: ==)
print("PoolDocument roundtrip ok:", roundtripMatches)

// Forgiving of a hand edit that drops createdWith and adds an unknown key.
let minimalJSON = """
{"name": "Hand-edited", "rules": [{"range": "GEN.1.1"}], "notes": "ignored on purpose"}
""".data(using: .utf8)!
let minimalDoc = try! PoolDocument.decode(from: minimalJSON)
print("forgiving decode (no createdWith, extra key):", minimalDoc.name, minimalDoc.createdWith == nil, minimalDoc.rules.map(\.range.key))

// Specific about what it refuses.
func expectError(_ label: String, _ json: String, _ expected: PoolDocumentError) {
    do {
        _ = try PoolDocument.decode(from: json.data(using: .utf8)!)
        print("FAIL \(label): expected \(expected), decoded without error")
    } catch let error as PoolDocumentError {
        print(error == expected ? "ok   \(label) -> \(error)" : "FAIL \(label) -> \(error) (expected \(expected))")
    } catch {
        print("FAIL \(label): unexpected error type \(error)")
    }
}
expectError("no name", #"{"rules": [{"range": "GEN.1.1"}]}"#, .missingName)
expectError("empty name", #"{"name": "", "rules": [{"range": "GEN.1.1"}]}"#, .missingName)
expectError("no rules key", #"{"name": "X"}"#, .missingRules)
expectError("empty rules", #"{"name": "X", "rules": []}"#, .noRules)
// "PSA.999.1" (a chapter no book has) is syntactically well-formed — a range
// naming something the canon doesn't have is a *validation* question
// (`VersePoolResolver`/`PoolValidationReport`), not a decode error, and
// resolves to zero verses rather than failing to parse. What actually fails
// to decode is a key the string grammar itself rejects: an empty chapter
// field.
expectError("bad range", #"{"name": "X", "rules": [{"range": "PSA..1"}]}"#, .invalidRange("PSA..1"))
expectError("not an object", #"[1, 2, 3]"#, .notAnObject)

// WEB's Textus-Receptus-only gaps (docs/translation-json-schema.md) are
// exactly where import validation earns its keep: resolving fine against the
// canon, absent from WEB.
let webGapRules = ["LUK.17.36", "ACT.8.37", "ACT.15.34", "ACT.24.7"].map { PoolRule(range: VerseRange(key: $0)!) }
let webGapReport = PoolValidationReport.validate(rules: webGapRules, translationID: "WEB")
print("WEB gap report: verseCount =", webGapReport.verseCount, "missing =", webGapReport.missingInTranslation.map(\.key).sorted())

// The guardrail: a pool that resolves to nothing must be refused, not saved.
let emptyReport = PoolValidationReport.validate(rules: [PoolRule(range: VerseRange(key: "PSA.137.1")!, isExclusion: true)], translationID: "WEB")
print("empty-rules-only-exclusion resolvesToNothing:", emptyReport.resolvesToNothing)

// MARK: - PoolTextFormat round trip

let textInput = """
- Ps 23
* Rom 8:28-39

Blurble 3:1
Jn 3:16
"""
let textRead = PoolTextFormat.read(textInput)
print("text read ranges:", textRead.ranges.map(\.key))
print("text read failures:", textRead.failures.map { "line \($0.line): \($0.text)" })

let writtenText = PoolTextFormat.write(textRead.ranges, translationID: "WEB")
let reread = PoolTextFormat.read(writtenText)
print("text write/reread roundtrip:", reread.ranges.map(\.key) == textRead.ranges.map(\.key), "->", reread.ranges.map(\.key))
