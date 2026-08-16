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
