import Foundation
import Observation

/// Codable mirror of `CGRect` (four `Double`s), since `CGRect` itself doesn't
/// round-trip cleanly through `Codable` across platforms.
private struct CodableRect: Codable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = Double(rect.origin.x)
        y = Double(rect.origin.y)
        width = Double(rect.size.width)
        height = Double(rect.size.height)
    }

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

/// A `Codable` wrapper mirroring `AppSettings`, but encoding `overlayFrame` as
/// four plain `Double`s instead of relying on `CGRect`'s own `Codable` conformance.
private struct StoredSettings: Codable {
    var theme: GradientTheme
    var refreshMinutes: Int
    var font: FontChoice
    var overlayEnabled: Bool
    var overlayFrame: CodableRect
    var fontScale: Double
    var showReference: Bool
    var translationID: String
    var language: AppLanguage
    var cornerRadius: Double
    var opacity: Double
    var positionLocked: Bool
    var clickThrough: Bool

    /// Accepts blobs written before `refreshMinutes` replaced the fixed
    /// `frequency` enum, so upgrading doesn't silently reset the user's
    /// settings to defaults.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theme = try container.decode(GradientTheme.self, forKey: .theme)
        // Added after the first release: absent in older blobs.
        font = try container.decodeIfPresent(FontChoice.self, forKey: .font) ?? .default
        overlayEnabled = try container.decode(Bool.self, forKey: .overlayEnabled)
        overlayFrame = try container.decode(CodableRect.self, forKey: .overlayFrame)
        fontScale = try container.decode(Double.self, forKey: .fontScale)
        showReference = try container.decode(Bool.self, forKey: .showReference)
        // Translation selection used to be a `Set<String>` of enabled
        // translations (verse selection drew randomly from whichever were
        // ticked). That's gone — a single translation now — so an older blob
        // migrates to its first previously-enabled id, keeping the pick
        // stable rather than reshuffling to the bundled default.
        if let single = try container.decodeIfPresent(String.self, forKey: .translationID) {
            translationID = single
        } else if let legacySet = try container.decodeIfPresent(Set<String>.self, forKey: .enabledTranslationIDs), let first = legacySet.sorted().first {
            translationID = first
        } else {
            translationID = BundledTranslations.defaultID
        }
        // Added when the language switch shipped: absent in older blobs.
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .systemDefault
        cornerRadius = try container.decode(Double.self, forKey: .cornerRadius)
        opacity = try container.decode(Double.self, forKey: .opacity)
        // Added after `clickThrough` was retired, so it's absent in older blobs.
        // Anyone who had click-through switched on had already chosen this
        // behaviour, so their setting carries over rather than resetting.
        let legacyClickThrough = try container.decode(Bool.self, forKey: .clickThrough)
        clickThrough = legacyClickThrough
        positionLocked = try container.decodeIfPresent(Bool.self, forKey: .positionLocked) ?? legacyClickThrough

        if let minutes = try container.decodeIfPresent(Int.self, forKey: .refreshMinutes) {
            refreshMinutes = minutes
        } else if let legacy = try container.decodeIfPresent(
            UpdateFrequency.self, forKey: .frequency
        ) {
            refreshMinutes = Int(legacy.interval / 60)
        } else {
            refreshMinutes = AppSettings.default.refreshMinutes
        }
    }

    /// Written explicitly because `CodingKeys` carries a legacy `frequency` case
    /// with no backing property, which blocks the synthesized encoder.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(theme, forKey: .theme)
        try container.encode(refreshMinutes, forKey: .refreshMinutes)
        try container.encode(font, forKey: .font)
        try container.encode(overlayEnabled, forKey: .overlayEnabled)
        try container.encode(overlayFrame, forKey: .overlayFrame)
        try container.encode(fontScale, forKey: .fontScale)
        try container.encode(showReference, forKey: .showReference)
        try container.encode(translationID, forKey: .translationID)
        try container.encode(language, forKey: .language)
        try container.encode(cornerRadius, forKey: .cornerRadius)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(positionLocked, forKey: .positionLocked)
        try container.encode(clickThrough, forKey: .clickThrough)
    }

    private enum CodingKeys: String, CodingKey {
        case theme, refreshMinutes, font, overlayEnabled, overlayFrame
        case fontScale, showReference, translationID, language, cornerRadius, opacity, positionLocked, clickThrough
        /// Legacy keys, decoded but never written.
        case frequency, enabledTranslationIDs
    }

    init(_ settings: AppSettings) {
        theme = settings.theme
        refreshMinutes = settings.refreshMinutes
        font = settings.font
        overlayEnabled = settings.overlayEnabled
        overlayFrame = CodableRect(settings.overlayFrame)
        fontScale = settings.fontScale
        showReference = settings.showReference
        translationID = settings.translationID
        language = settings.language
        cornerRadius = settings.cornerRadius
        opacity = settings.opacity
        positionLocked = settings.positionLocked
        clickThrough = settings.clickThrough
    }

    var settings: AppSettings {
        AppSettings(
            theme: theme,
            refreshMinutes: refreshMinutes,
            font: font,
            overlayEnabled: overlayEnabled,
            overlayFrame: overlayFrame.rect,
            fontScale: fontScale,
            showReference: showReference,
            translationID: translationID,
            language: language,
            cornerRadius: cornerRadius,
            opacity: opacity,
            positionLocked: positionLocked,
            clickThrough: clickThrough
        )
    }
}

/// Persists `AppSettings` to the shared App Group container so the app and
/// widget extension can both read/write the same values. Degrades gracefully
/// to `UserDefaults.standard` when the App Group is unavailable (e.g. no
/// signing team configured), in which case the widget will only ever see
/// `AppSettings.default`.
@MainActor
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    private static let key = "appSettings"
    private static let probeKey = "sharedDomainProbe"

    /// Whether the shared domain can actually be written to and read back.
    ///
    /// Neither obvious test works here. `UserDefaults(suiteName:)` returns a
    /// usable object for any string — a suite name is just a domain, entitlement
    /// or not — and on macOS
    /// `containerURL(forSecurityApplicationGroupIdentifier:)` likewise returns a
    /// path for a process that isn't sandboxed. Both are therefore always true,
    /// which is why `isShared` was always true and the app's "widgets can't see
    /// your settings" warning never appeared, including in the builds it was
    /// written for.
    ///
    /// A round trip is the honest test: where the App Group is denied — a
    /// sandboxed build without the entitlement — the write is dropped and the
    /// read comes back empty.
    ///
    /// It tests this process only. It cannot tell whether the widget, which is
    /// sandboxed on its own terms, can reach the same domain, so a true result
    /// means "nothing is stopping us from our side" rather than a guarantee that
    /// sharing works end to end.
    private static func isUsable(_ defaults: UserDefaults) -> Bool {
        let token = "\(ProcessInfo.processInfo.processIdentifier)-\(Date().timeIntervalSince1970)"
        defaults.set(token, forKey: probeKey)
        let readBack = defaults.string(forKey: probeKey)
        defaults.removeObject(forKey: probeKey)
        return readBack == token
    }

    private let defaults: UserDefaults

    /// True when the App Group container was reachable (i.e. app<->widget sharing works).
    let isShared: Bool

    var settings: AppSettings {
        didSet {
            persist()
        }
    }

    private init() {
        if let shared = UserDefaults(suiteName: AppGroup.suiteName), Self.isUsable(shared) {
            defaults = shared
            isShared = true
        } else {
            defaults = .standard
            isShared = false
        }
        settings = Self.read(from: defaults) ?? .default
    }

    /// Re-reads settings from disk. The widget process calls this at the start
    /// of every timeline computation, since the app may have changed settings
    /// since the widget's own copy was loaded.
    func reload() {
        settings = Self.read(from: defaults) ?? .default
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(StoredSettings(settings)) else { return }
        defaults.set(data, forKey: Self.key)
    }

    private static func read(from defaults: UserDefaults) -> AppSettings? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let stored = try? JSONDecoder().decode(StoredSettings.self, from: data) else { return nil }
        return stored.settings
    }
}
