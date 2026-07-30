# Bibliada — build spec (authoritative contract)

macOS app + widget that shows a random Bible verse on a customizable gradient card.

Target: macOS 26 (deployment target 15.0), Xcode 26, Swift 6, SwiftUI.
Repo root: `/Users/dutov/Life/Personal/bibliada`

## Two display modes (deliberate design)

1. **Widget mode** — real WidgetKit widget (Desktop / Notification Center). System-fixed
   sizes only (small/medium/large/extraLarge). Update frequency is *best-effort*: the
   TimelineProvider requests entries at the chosen interval, macOS honors it approximately
   (budget ~40–70 reloads/day, so 1h is realistic, sub-hourly is not offered).
2. **Desktop overlay mode** — borderless, resizable, always-behind-other-windows NSPanel
   pinned at desktop level. **Arbitrary rectangular size** and exact timer-driven updates.
   This is where "any custom size" and "exact frequency" actually live.

Not doing: wallpaper image compositing (breaks dynamic wallpapers, needs polling) or
Lock Screen (no public API on macOS).

## Verse source

Public domain: **World English Bible (WEB)** via `https://bible-api.com`.
- Selection: pick a random reference from the bundled curated catalog (`verses.json`).
- Text: `GET https://bible-api.com/<url-encoded reference>?translation=web`
- Fallback: the bundled catalog already carries WEB text, so the app works fully offline
  and the widget can render instantly with zero network.
- No API key. Be polite: 8s timeout, one request per update, no retries beyond 1.

## File layout

```
project.yml                       # XcodeGen spec (Agent 2)
Bibliada.xcodeproj                # generated, gitignored
Makefile / build.sh               # generate + build + install (Agent 2)
Shared/                           # compiled into BOTH app and widget targets (Agent 1)
  Verse.swift
  GradientTheme.swift
  AppSettings.swift
  SettingsStore.swift
  VerseProvider.swift
  VerseCache.swift
  VerseCardView.swift
  Resources/verses.json
App/                              # main app target (Agent 3)
  BibliadaApp.swift
  AppState.swift
  OverlayWindowController.swift
  SettingsView.swift
  Info.plist
  Bibliada.entitlements
  Assets.xcassets
Widget/                           # widget extension target (Agent 4)
  BibliadaWidgetBundle.swift
  VerseTimelineProvider.swift
  VerseWidgetConfiguration.swift
  Info.plist
  BibliadaWidget.entitlements
```

## Identifiers

- App bundle id: `com.bibliada.Bibliada`
- Widget bundle id: `com.bibliada.Bibliada.Widget`
- Widget `kind`: `com.bibliada.verse-widget`
- App Group: `group.com.bibliada.shared`
- Signing: `DEVELOPMENT_TEAM` comes from the `BIBLIADA_TEAM_ID` env var, empty by default.
  With no team, App Groups are unavailable → `SettingsStore` must degrade gracefully to
  `UserDefaults.standard` (app-only; widget then shows defaults). Document this.

## Shared API contract (Agent 1 implements EXACTLY this; Agents 3 & 4 code against it)

```swift
// Verse.swift
struct Verse: Codable, Hashable, Sendable, Identifiable {
    var id: String { reference }
    let reference: String      // "John 3:16"
    let text: String           // whitespace-trimmed, newlines collapsed to spaces
    let translation: String    // "WEB"
}

// GradientTheme.swift
struct RGBAColor: Codable, Hashable, Sendable {
    var red: Double, green: Double, blue: Double, alpha: Double
    init(_ color: Color)                  // via NSColor sRGB conversion
    init(red: Double, green: Double, blue: Double, alpha: Double = 1)
    var color: Color { get }
}

struct GradientTheme: Codable, Hashable, Sendable {
    var startColor: RGBAColor
    var endColor: RGBAColor
    var angle: Double                     // degrees, 0 = top→bottom, clockwise
    var textColor: RGBAColor
    var gradient: LinearGradient { get }   // resolves `angle` to unit points
    static let presets: [ThemePreset]
    static let `default`: GradientTheme    // must be one of the presets
}
struct ThemePreset: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let theme: GradientTheme
}

// AppSettings.swift
enum UpdateFrequency: String, Codable, CaseIterable, Identifiable, Sendable {
    case hourly, every3Hours, every6Hours, every12Hours, daily
    var id: String { rawValue }
    var interval: TimeInterval { get }
    var displayName: String { get }        // "Every hour", "Every 3 hours", … "Once a day"
}

struct AppSettings: Codable, Sendable, Equatable {
    var theme: GradientTheme
    var frequency: UpdateFrequency
    var overlayEnabled: Bool
    var overlayFrame: CGRect               // arbitrary rectangle, screen coords
    var fontScale: Double                  // 0.6…2.0, 1.0 default
    var showReference: Bool
    var cornerRadius: Double               // 0…40
    var opacity: Double                    // 0.2…1.0
    var clickThrough: Bool                 // overlay ignores mouse events
    static let `default`: AppSettings      // overlayFrame 360x360 near top-right
}

// SettingsStore.swift  — @MainActor, works in app AND widget process
@MainActor @Observable final class SettingsStore {
    static let shared: SettingsStore
    var settings: AppSettings { get set }  // setter persists immediately (JSON in shared defaults, key "appSettings")
    /// true when the App Group container was reachable (i.e. app↔widget sharing works)
    let isShared: Bool
    func reload()                          // re-read from disk (widget calls this per timeline)
}

// VerseCache.swift — last shown verse, shared between processes
struct CachedVerse: Codable, Sendable { let verse: Verse; let fetchedAt: Date }
enum VerseCache {
    static func load() -> CachedVerse?
    static func save(_ verse: Verse)
}

// VerseProvider.swift
actor VerseProvider {
    static let shared: VerseProvider
    /// Never throws. Tries bible-api.com, falls back to the bundled catalog. Also writes VerseCache.
    func nextVerse() async -> Verse
    /// Synchronous, offline, cheap. Used for widget previews/placeholders.
    static func bundledRandom() -> Verse
    static var catalog: [Verse] { get }    // decoded from Resources/verses.json, cached
}

// VerseCardView.swift
struct VerseCardView: View {
    let verse: Verse
    let settings: AppSettings
    init(verse: Verse, settings: AppSettings)
}
```

`VerseCardView` requirements: gradient background honoring `theme.angle`, verse text in
`.system(.body, design: .serif)`-derived font scaled by `fontScale`, reference below in a
smaller semibold caps style, `minimumScaleFactor(0.5)` + `ViewThatFits`/`GeometryReader` so
it reads well from 150×150 up to 1400×900. Rounded corners per `cornerRadius`, whole card at
`opacity`. Must look native-macOS-clean: generous padding, subtle text shadow, no borders.

## Cross-agent rules

- Do not create or modify files outside your assigned directory.
- Swift 6 strict concurrency must compile clean. No force-unwraps, no `try!`.
- No third-party dependencies.
- Do not run `xcodegen`/`xcodebuild` yourself — the orchestrator integrates and builds.
