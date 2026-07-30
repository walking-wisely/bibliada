import SwiftUI
import AppKit

/// A simple, Codable, Sendable RGBA color value, independent of `Color`'s
/// non-Codable storage. Used so themes can be persisted to `UserDefaults`.
struct RGBAColor: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Converts a SwiftUI `Color` to sRGB components via `NSColor`.
    /// Falls back to opaque black if the color space conversion fails.
    init(_ color: Color) {
        let nsColor = NSColor(color)
        if let converted = nsColor.usingColorSpace(.sRGB) {
            self.red = Double(converted.redComponent)
            self.green = Double(converted.greenComponent)
            self.blue = Double(converted.blueComponent)
            self.alpha = Double(converted.alphaComponent)
        } else {
            self.red = 0
            self.green = 0
            self.blue = 0
            self.alpha = 1
        }
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

/// A two-stop linear gradient theme with a companion text color, persisted as part of
/// `AppSettings` and rendered by `VerseCardView`.
struct GradientTheme: Codable, Hashable, Sendable {
    var startColor: RGBAColor
    var endColor: RGBAColor
    /// Degrees, 0 = top→bottom, clockwise.
    var angle: Double
    var textColor: RGBAColor

    /// Resolves `angle` (degrees, 0 = top→bottom, clockwise) to unit-space start/end points.
    var gradient: LinearGradient {
        let radians = (angle - 90) * .pi / 180
        let dx = cos(radians)
        let dy = sin(radians)
        // Project a unit vector centered at (0.5, 0.5) onto the unit square.
        let start = UnitPoint(x: 0.5 - dx / 2, y: 0.5 - dy / 2)
        let end = UnitPoint(x: 0.5 + dx / 2, y: 0.5 + dy / 2)
        return LinearGradient(
            colors: [startColor.color, endColor.color],
            startPoint: start,
            endPoint: end
        )
    }

    static let presets: [ThemePreset] = [
        ThemePreset(
            name: "Indigo Dusk",
            theme: GradientTheme(
                startColor: RGBAColor(red: 0.18, green: 0.15, blue: 0.42),
                endColor: RGBAColor(red: 0.42, green: 0.24, blue: 0.62),
                angle: 135,
                textColor: RGBAColor(red: 1, green: 1, blue: 1)
            )
        ),
        ThemePreset(
            name: "Dawn Peach",
            theme: GradientTheme(
                startColor: RGBAColor(red: 0.98, green: 0.78, blue: 0.62),
                endColor: RGBAColor(red: 0.93, green: 0.51, blue: 0.55),
                angle: 135,
                textColor: RGBAColor(red: 0.25, green: 0.1, blue: 0.12)
            )
        ),
        ThemePreset(
            name: "Forest",
            theme: GradientTheme(
                startColor: RGBAColor(red: 0.08, green: 0.28, blue: 0.2),
                endColor: RGBAColor(red: 0.2, green: 0.45, blue: 0.28),
                angle: 160,
                textColor: RGBAColor(red: 1, green: 1, blue: 1)
            )
        ),
        ThemePreset(
            name: "Slate",
            theme: GradientTheme(
                startColor: RGBAColor(red: 0.22, green: 0.26, blue: 0.31),
                endColor: RGBAColor(red: 0.42, green: 0.47, blue: 0.53),
                angle: 145,
                textColor: RGBAColor(red: 1, green: 1, blue: 1)
            )
        ),
        ThemePreset(
            name: "Sand",
            theme: GradientTheme(
                startColor: RGBAColor(red: 0.94, green: 0.87, blue: 0.71),
                endColor: RGBAColor(red: 0.82, green: 0.68, blue: 0.48),
                angle: 135,
                textColor: RGBAColor(red: 0.28, green: 0.2, blue: 0.09)
            )
        ),
        ThemePreset(
            name: "Midnight",
            theme: GradientTheme(
                startColor: RGBAColor(red: 0.02, green: 0.04, blue: 0.12),
                endColor: RGBAColor(red: 0.13, green: 0.16, blue: 0.32),
                angle: 120,
                textColor: RGBAColor(red: 0.9, green: 0.92, blue: 1)
            )
        ),
        ThemePreset(
            name: "Ocean",
            theme: GradientTheme(
                startColor: RGBAColor(red: 0.02, green: 0.32, blue: 0.44),
                endColor: RGBAColor(red: 0.09, green: 0.58, blue: 0.62),
                angle: 145,
                textColor: RGBAColor(red: 1, green: 1, blue: 1)
            )
        ),
        ThemePreset(
            name: "Plum",
            theme: GradientTheme(
                startColor: RGBAColor(red: 0.28, green: 0.09, blue: 0.24),
                endColor: RGBAColor(red: 0.52, green: 0.19, blue: 0.38),
                angle: 135,
                textColor: RGBAColor(red: 1, green: 1, blue: 1)
            )
        ),
    ]

    static let `default`: GradientTheme = presets[0].theme
}

struct ThemePreset: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let theme: GradientTheme
}
