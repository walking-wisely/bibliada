import Foundation
import CoreGraphics
import SwiftUI

/// How often the overlay/widget should refresh to a new verse.
enum UpdateFrequency: String, Codable, CaseIterable, Identifiable, Sendable {
    case hourly
    case every3Hours
    case every6Hours
    case every12Hours
    case daily

    var id: String { rawValue }

    var interval: TimeInterval {
        switch self {
        case .hourly: return 60 * 60
        case .every3Hours: return 3 * 60 * 60
        case .every6Hours: return 6 * 60 * 60
        case .every12Hours: return 12 * 60 * 60
        case .daily: return 24 * 60 * 60
        }
    }

    var displayName: String { displayName(.en) }

    func displayName(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.hourly, .en): return "Every hour"
        case (.hourly, .uk): return "Щогодини"
        case (.every3Hours, .en): return "Every 3 hours"
        case (.every3Hours, .uk): return "Кожні 3 години"
        case (.every6Hours, .en): return "Every 6 hours"
        case (.every6Hours, .uk): return "Кожні 6 годин"
        case (.every12Hours, .en): return "Every 12 hours"
        case (.every12Hours, .uk): return "Кожні 12 годин"
        case (.daily, .en): return "Once a day"
        case (.daily, .uk): return "Раз на день"
        }
    }
}

/// The typeface used for verse text.
///
/// Either one of the four system designs — which track the user's system font
/// and are always available to a sandboxed widget extension — or a specific
/// installed font family by name. Stored as a plain string so the persisted
/// form stays readable and forward-compatible: system designs use a reserved
/// `system:` prefix, everything else is a family name.
enum FontChoice: Codable, Hashable, Sendable {
    case system(SystemDesign)
    case family(String)

    enum SystemDesign: String, Codable, CaseIterable, Identifiable, Sendable {
        case serif
        case standard
        case rounded
        case monospaced

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .serif: return "System Serif"
            case .standard: return "System Sans"
            case .rounded: return "System Rounded"
            case .monospaced: return "System Mono"
            }
        }

        var swiftUIDesign: Font.Design {
            switch self {
            case .serif: return .serif
            case .standard: return .default
            case .rounded: return .rounded
            case .monospaced: return .monospaced
            }
        }
    }

    static let `default` = FontChoice.system(.serif)

    var displayName: String {
        switch self {
        case .system(let design): return design.displayName
        case .family(let name): return name
        }
    }

    // MARK: Codable via a single string

    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(storageValue: raw)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storageValue)
    }

    var storageValue: String {
        switch self {
        case .system(let design): return "system:\(design.rawValue)"
        case .family(let name): return name
        }
    }

    init(storageValue raw: String) {
        guard raw.hasPrefix("system:") else {
            self = raw.isEmpty ? .default : .family(raw)
            return
        }
        let name = String(raw.dropFirst("system:".count))
        self = SystemDesign(rawValue: name).map(FontChoice.system) ?? .default
    }
}

/// The full set of user-configurable app/widget/overlay settings, persisted via `SettingsStore`.
struct AppSettings: Codable, Sendable, Equatable {
    /// Bounds for `refreshMinutes`: one minute to 24 hours.
    static let refreshMinutesRange = 1...(24 * 60)

    var theme: GradientTheme
    /// Refresh cadence in minutes. The desktop overlay honors this exactly,
    /// which is why it's free-form rather than a fixed set of choices.
    var refreshMinutes: Int
    /// Typeface for the verse text.
    var font: FontChoice
    var overlayEnabled: Bool
    /// Arbitrary rectangle, screen coordinates.
    var overlayFrame: CGRect
    /// 0.6...2.0, 1.0 default.
    var fontScale: Double
    var showReference: Bool
    /// Which single bundled translation verse selection draws from. Only one
    /// at a time — picking more than one would mean the verse's language
    /// changes at random between refreshes, which isn't a real choice, just
    /// an ungoverned one. Callers that read it directly should still treat an
    /// unrecognized id as "use WEB" rather than assuming it's always valid
    /// (see `TranslationCatalog.randomVerse`).
    var translationID: String
    /// The language every label, button and menu item in the app is drawn in.
    /// Independent of `translationID` — see `AppLanguage`.
    var language: AppLanguage
    /// 0...40.
    var cornerRadius: Double
    /// 0.2...1.0.
    var opacity: Double
    /// Locks the desktop card in place: it stops responding to the mouse, so it
    /// can't be dragged or resized by accident. Clicks land on whatever is
    /// beneath it, as they would if it weren't there.
    ///
    /// This is what the old `clickThrough` did — the behaviour was useful, the
    /// name described the side effect rather than the reason anyone wanted it.
    var positionLocked: Bool
    /// No longer read by anything: the overlay always accepts its own mouse
    /// events unless `positionLocked` is set. Kept so settings saved by earlier versions
    /// still decode, and so anyone who had it switched on isn't left with an
    /// overlay they can't grab and no toggle to turn it off.
    var clickThrough: Bool

    /// Clamped cadence in seconds, for the overlay's timer.
    var refreshInterval: TimeInterval {
        let clamped = min(max(refreshMinutes, Self.refreshMinutesRange.lowerBound),
                          Self.refreshMinutesRange.upperBound)
        return TimeInterval(clamped) * 60
    }

    /// The coarse cadence handed to WidgetKit.
    ///
    /// A widget cannot honor sub-hourly refreshes — macOS budgets widget reloads
    /// to roughly 40–70 a day — so anything faster than hourly is reported as
    /// hourly rather than pretending. Values in between round down to the
    /// nearest cadence the system can plausibly deliver.
    var widgetFrequency: UpdateFrequency {
        switch refreshMinutes {
        case ..<(3 * 60): return .hourly
        case ..<(6 * 60): return .every3Hours
        case ..<(12 * 60): return .every6Hours
        case ..<(24 * 60): return .every12Hours
        default: return .daily
        }
    }

    /// Human-readable form of `refreshMinutes`, e.g. "every 1 h 30 min".
    var refreshDescription: String {
        let hours = refreshMinutes / 60
        let minutes = refreshMinutes % 60
        switch (hours, minutes) {
        case (0, let m): return m == 1 ? "every minute" : "every \(m) min"
        case (let h, 0): return h == 1 ? "every hour" : "every \(h) h"
        case (let h, let m): return "every \(h) h \(m) min"
        }
    }

    static let `default` = AppSettings(
        theme: .default,
        refreshMinutes: 60,
        font: .default,
        overlayEnabled: true,
        overlayFrame: CGRect(x: 1540, y: 60, width: 360, height: 360),
        fontScale: 1.0,
        showReference: true,
        translationID: BundledTranslations.defaultID,
        language: .systemDefault,
        cornerRadius: 20,
        opacity: 1.0,
        // Locked from the start: the card is meant to sit still and be read, and
        // a stray drag on the desktop shouldn't move it. Positioning is done from
        // Size & Position (the widget grid, or the fields), and the lock comes off
        // from there, the menu bar, or the card's own right-click menu.
        positionLocked: true,
        clickThrough: false
    )
}
