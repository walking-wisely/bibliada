import Foundation

/// A self-contained set of localized strings, looked up through the same
/// `AppLanguage.t(_:)` call as `Loc`.
///
/// `Loc` is one enum plus one table in one file, which is right for the strings
/// that were there before pools and wrong for anything built by more than one
/// person at a time: Swift can't add cases to an enum from another file, so
/// every feature adding UI strings would have to edit the same two places.
/// Conforming a feature's own enum to this protocol keeps its strings in its
/// own file, with the same fall back to English and then to the raw key that
/// `Loc` has.
///
/// `Loc` itself conforms, so `language.t(.quit)` keeps working unchanged.
protocol LocalizedKeySet: RawRepresentable, Hashable where RawValue == String {
    static var table: [Self: [AppLanguage: String]] { get }
}

/// The original string set. Declared here rather than in `Localization.swift`
/// so that file needs no edit to gain the conformance.
extension Loc: LocalizedKeySet {}

extension AppLanguage {
    func t<Key: LocalizedKeySet>(_ key: Key) -> String {
        Key.table[key]?[self] ?? Key.table[key]?[.en] ?? key.rawValue
    }

    /// `t(_:)` with `%@`-style placeholders substituted in order.
    func t<Key: LocalizedKeySet>(_ key: Key, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }
}
