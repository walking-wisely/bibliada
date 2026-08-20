import Foundation

/// Plain-text interchange for verse pools: one reference per line, read and
/// written through the same `ReferenceParser` behind the omnibar and the
/// `.bibliadapool` JSON path — a string that parses in one parses in all
/// three.
///
/// This is the format that actually circulates. Nobody pastes a verse list
/// into a chat message as JSON; they type "Ps 23" on its own line. So `read`
/// has to tolerate the mess real text arrives in — blank lines, a leading
/// bullet or dash from a note-taking app, stray whitespace — and it must
/// report a bad line individually rather than dropping it: silently losing
/// one of fifty pasted references is exactly the failure mode the design doc
/// rules out for import.
enum PoolTextFormat {
    /// A line that didn't parse to a reference, kept with its 1-based line
    /// number so an import report can point at it directly ("line 7: ...").
    struct LineFailure: Hashable, Sendable {
        let line: Int
        let text: String
        let reason: ReferenceParseFailure.Reason
    }

    struct ReadResult: Hashable, Sendable {
        var ranges: [VerseRange]
        var failures: [LineFailure]

        var isEmpty: Bool { ranges.isEmpty && failures.isEmpty }
    }

    /// Parses `text` a line at a time. A line is skipped, not reported, only
    /// when it carries nothing to parse at all (blank, or only a bullet
    /// marker); everything else goes through `ReferenceParser.parse`, and any
    /// fragment it can't make sense of becomes a `LineFailure` rather than
    /// vanishing.
    ///
    /// A single line may still hold more than one reference — the parser's
    /// own `;`/`,` fragment splitting still applies, so "Ps 23; Rom 8:28" on
    /// one line yields two ranges — this only adds line-oriented reporting on
    /// top of it.
    static func read(_ text: String) -> ReadResult {
        var ranges: [VerseRange] = []
        var failures: [LineFailure] = []
        for (offset, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let line = strippingBullet(rawLine.trimmingCharacters(in: .whitespaces))
            guard !line.isEmpty else { continue }
            let parsed = ReferenceParser.parse(line)
            ranges.append(contentsOf: parsed.references.map(\.range))
            for failure in parsed.failures {
                failures.append(LineFailure(line: offset + 1, text: failure.source, reason: failure.reason))
            }
        }
        return ReadResult(ranges: ranges, failures: failures)
    }

    /// One reference per line, in the given order. `translationID` only
    /// picks display book names (`Genesis` vs `Буття`) — the canonical range
    /// is what a subsequent `read` reparses, so a round trip is exact even
    /// across a language switch between export and import.
    static func write(_ ranges: [VerseRange], translationID: String) -> String {
        ranges
            .map { ReferenceParser.displayString(for: $0, translationID: translationID) }
            .joined(separator: "\n")
    }

    /// Strips a leading "- ", "* " or "• " — the marker most note apps and
    /// chat clients prepend to a pasted list item — so "- Ps 23" reads the
    /// same as "Ps 23". Only leading punctuation is touched; anything else
    /// (including a book name that happens to start with a hyphenated
    /// number) is left for the parser to accept or reject on its own terms.
    private static func strippingBullet(_ line: String) -> String {
        var text = Substring(line)
        while let first = text.first, first == "-" || first == "*" || first == "\u{2022}" {
            text = text.dropFirst()
        }
        return text.trimmingCharacters(in: .whitespaces)
    }
}
