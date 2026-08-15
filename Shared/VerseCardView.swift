import SwiftUI

/// Renders a verse on a gradient card. Used by both the desktop overlay
/// (arbitrary size, up to ~1400x900) and the widget (fixed system sizes,
/// down to ~150x150), so all sizing is derived from the available space
/// rather than fixed point sizes.
struct VerseCardView: View {
    let verse: Verse
    let settings: AppSettings

    init(verse: Verse, settings: AppSettings) {
        self.verse = verse
        self.settings = settings
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let shortestSide = min(size.width, size.height)
            let padding = max(shortestSide * 0.09, 10)
            let bodyFontSize = clamp(shortestSide * 0.11, min: 11, max: 46) * settings.fontScale
            let referenceFontSize = clamp(shortestSide * 0.052, min: 9, max: 20) * settings.fontScale

            ZStack {
                settings.theme.gradient

                VStack(alignment: .center, spacing: padding * 0.4) {
                    Spacer(minLength: 0)

                    Text(verse.text)
                        .font(bodyFont(size: bodyFontSize))
                        .foregroundStyle(settings.theme.textColor.color)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                        .lineLimit(nil)
                        .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)

                    if settings.showReference {
                        Text(verse.reference.uppercased())
                            .font(referenceFont(size: referenceFontSize))
                            .tracking(1.2)
                            .foregroundStyle(settings.theme.textColor.color.opacity(0.82))
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.5)
                            .lineLimit(2)
                            .shadow(color: .black.opacity(0.15), radius: 1.5, x: 0, y: 1)
                    }

                    Spacer(minLength: 0)
                }
                .padding(padding)
                .frame(width: size.width, height: size.height)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: settings.cornerRadius, style: .continuous))
            .opacity(settings.opacity)
        }
    }

    private func bodyFont(size: Double) -> Font {
        switch settings.font {
        case .system(let design):
            return .system(size: size, weight: .medium, design: design.swiftUIDesign)
        case .family(let name):
            // `Font.custom(_:size:)` silently falls back to the system font if the
            // family isn't installed, which is the behavior we want — a font that
            // was uninstalled shouldn't leave the card blank.
            return .custom(name, size: size)
        }
    }

    /// The reference keeps its own treatment when a system design is in use, but
    /// follows a chosen family so the card reads as one typeface.
    private func referenceFont(size: Double) -> Font {
        switch settings.font {
        case .system:
            return .system(size: size, weight: .semibold, design: .rounded)
        case .family(let name):
            return .custom(name, size: size).weight(.semibold)
        }
    }

    private func clamp(_ value: Double, min lower: Double, max upper: Double) -> Double {
        Swift.min(Swift.max(value, lower), upper)
    }
}

#Preview("Widget Small — 150x150") {
    VerseCardView(
        verse: Verse(
            reference: "John 3:16",
            text: "For God so loved the world, that he gave his one and only Son, that whoever believes in him should not perish, but have eternal life.",
            translation: "WEB"
        ),
        settings: .default
    )
    .frame(width: 150, height: 150)
}

#Preview("Widget Medium — 340x160") {
    VerseCardView(
        verse: Verse(
            reference: "Philippians 4:13",
            text: "I can do all things through Christ, who strengthens me.",
            translation: "WEB"
        ),
        settings: .default
    )
    .frame(width: 340, height: 160)
}

#Preview("Overlay Square — 360x360") {
    VerseCardView(
        verse: Verse(
            reference: "Psalm 23:1",
            text: "Yahweh is my shepherd: I shall lack nothing.",
            translation: "WEB"
        ),
        settings: .default
    )
    .frame(width: 360, height: 360)
}

#Preview("Overlay Large — 1400x900") {
    VerseCardView(
        verse: Verse(
            reference: "Isaiah 41:10",
            text: "Don't you be afraid, for I am with you. Don't be dismayed, for I am your God. I will strengthen you. Yes, I will help you. Yes, I will uphold you with the right hand of my righteousness.",
            translation: "WEB"
        ),
        settings: AppSettings(
            theme: GradientTheme.presets[6].theme,
            refreshMinutes: 1440,
            font: .default,
            overlayEnabled: true,
            overlayFrame: CGRect(x: 0, y: 0, width: 1400, height: 900),
            fontScale: 1.0,
            showReference: true,
            translationID: BundledTranslations.defaultID,
            cornerRadius: 32,
            opacity: 1.0,
            positionLocked: false,
            clickThrough: false
        )
    )
    .frame(width: 1400, height: 900)
}
