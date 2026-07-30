import AppIntents
import OSLog
import SwiftUI
import WidgetKit

@main
struct BibliadaWidgetBundle: WidgetBundle {
    var body: some Widget {
        VerseWidget()
    }
}

struct VerseWidget: Widget {
    let kind: String = "com.bibliada.verse-widget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: VerseWidgetConfigurationIntent.self,
            provider: VerseTimelineProvider()
        ) { entry in
            VerseWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    entry.settings.theme.gradient
                }
        }
        .configurationDisplayName("Bible Verse")
        .description("A random Bible verse on a gradient card. Each widget can have its own colours, its own schedule for changing the verse, and its own choice about showing the reference.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .containerBackgroundRemovable(false)
    }
}

/// Renders one timeline entry using the shared `VerseCardView`.
///
/// Widget size and corner radius are dictated entirely by the system (fixed
/// family sizes, automatic container shape/clipping) — unlike the desktop
/// overlay, a widget cannot be an arbitrary rectangle. So `AppSettings
/// .overlayFrame` and `AppSettings.cornerRadius` are intentionally *not* read
/// or applied specially here; `VerseCardView` uses its own internal
/// `cornerRadius` styling as usual, but the outer widget chrome (its actual
/// on-screen size/shape) is controlled by WidgetKit, not by those settings.
struct VerseWidgetEntryView: View {
    let entry: VerseEntry

    var body: some View {
        VerseCardView(verse: entry.verse, settings: entry.settings)
        #if DEBUG
            // Apple documents widget dimensions for iOS, iPadOS, visionOS and
            // watchOS, but not for macOS — there is no Mac table in the Human
            // Interface Guidelines. So the only trustworthy source for the sizes
            // the desktop actually uses is the widget measuring itself. Debug
            // builds log it; read the numbers back with:
            //
            //   log show --last 10m --predicate 'subsystem == "com.bibliada.widget"' --info
            //
            // Those are the sizes the Size & Position presets are meant to match.
            .overlay {
                GeometryReader { proxy in
                    Color.clear.onAppear {
                        Logger.widgetMetrics.info(
                            "widget rendered at \(proxy.size.width, privacy: .public)x\(proxy.size.height, privacy: .public)"
                        )
                    }
                }
            }
        #endif
    }
}

#if DEBUG
extension Logger {
    static let widgetMetrics = Logger(subsystem: "com.bibliada.widget", category: "metrics")
}
#endif
