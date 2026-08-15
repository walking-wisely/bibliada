import Foundation
import Security

/// Resolves the shared App Group suite name at runtime.
///
/// The entitlement files declare the group as
/// `$(TeamIdentifierPrefix)group.com.bibliada.shared` so one spelling works
/// unmodified for both Developer ID and Mac App Store signing; Xcode expands
/// that variable into the entitlements it embeds at build time. Swift code
/// doesn't get that expansion for free, so `UserDefaults(suiteName:)` and
/// `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` need the
/// literal, already-expanded identifier — read back here from the running
/// process's own code signature.
enum AppGroup {
    static let suiteName: String = {
        let prefix = teamIdentifierPrefix.map { "\($0)." } ?? ""
        return "\(prefix)group.com.bibliada.shared"
    }()

    /// The team identifier, as embedded in this process's code signature by
    /// codesign. `nil` for an unsigned build (e.g. no team configured), in
    /// which case callers fall back to the bare group name.
    private static let teamIdentifierPrefix: String? = {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        guard let value = SecTaskCopyValueForEntitlement(
            task,
            "com.apple.developer.team-identifier" as CFString,
            nil
        ) else { return nil }
        return value as? String
    }()
}
