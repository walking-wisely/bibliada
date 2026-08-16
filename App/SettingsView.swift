import AppKit
import SwiftUI

/// One of the four settings tabs, plus what its switcher button shows.
///
/// `TabView` only gets the native icon-above-label switcher (see the
/// reference screenshot this was built to match) when it's hosted inside a
/// real SwiftUI `Settings` scene. `SettingsView` is hosted in a plain
/// `NSWindow` instead — see `SettingsWindowController` for why — so `TabBar`
/// below hand-rolls a matching switcher, driven by this enum, rather than
/// falling back to `TabView`'s plain-text default.
private enum SettingsTab: CaseIterable {
    case appearance, sizePosition, verseChanges, general, about

    var systemImage: String {
        switch self {
        case .appearance: return "paintpalette"
        case .sizePosition: return "aspectratio"
        case .verseChanges: return "clock.arrow.circlepath"
        case .general: return "gearshape"
        case .about: return "info.circle"
        }
    }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .appearance: return language.t(.tabAppearance)
        case .sizePosition: return language.t(.tabSizePosition)
        case .verseChanges: return language.t(.tabVerseChanges)
        case .general: return language.t(.tabGeneral)
        case .about: return language.t(.tabAbout)
        }
    }
}

/// The Settings window, opened from the menu-bar extra. Four tabs: Appearance,
/// Size & Position, Verse changes, and General. Every control writes straight through
/// to `SettingsStore.shared.settings`, so changes persist and (where relevant)
/// apply live to an already-visible overlay via `AppState`'s settings poller.
struct SettingsView: View {
    private var settingsStore = SettingsStore.shared

    @State private var selectedTab: SettingsTab = .appearance

    private var language: AppLanguage { settingsStore.settings.language }

    var body: some View {
        VStack(spacing: 0) {
            TabBar(selectedTab: $selectedTab, language: language)
            Divider()
            selectedTabView
        }
        // Taller than the content strictly needs: Appearance now spends a fixed
        // strip at the top on the pinned preview, and without the extra height
        // the list underneath it would only show two rows at a time. 520×560 is
        // the size the window opens at; below that it's user-resizable down to
        // 300×500 — see `SettingsWindowController.minWindowSize`, which is what
        // actually enforces this floor.
        .frame(
            minWidth: 300, idealWidth: 520, maxWidth: .infinity,
            minHeight: 500, idealHeight: 560, maxHeight: .infinity
        )
    }

    @ViewBuilder
    private var selectedTabView: some View {
        switch selectedTab {
        case .appearance: AppearanceSettingsTab(settings: settingsBinding)
        case .sizePosition: SizePositionSettingsTab(settings: settingsBinding)
        case .verseChanges: UpdatesSettingsTab(settings: settingsBinding)
        case .general: GeneralSettingsTab(settings: settingsBinding)
        case .about: AboutSettingsTab(language: language)
        }
    }

    private var settingsBinding: Binding<AppSettings> {
        Binding(
            get: { settingsStore.settings },
            set: { settingsStore.settings = $0 }
        )
    }
}

/// The icon-above-label row of tab buttons, standing in for `TabView`'s own
/// switcher (see `SettingsTab`'s doc comment for why).
///
/// Four labeled buttons at 76pt each don't have anywhere to give: that's a
/// hard ~340pt floor on the whole bar regardless of what the window itself
/// is willing to shrink to, so a narrower window just clipped the overflow
/// instead of the bar actually getting smaller. `ViewThatFits` picks the
/// icon-only row once the labeled one no longer fits — same fix as
/// `SliderSettingRow` uses for its track — so the bar keeps shrinking down to
/// icon width instead of clipping.
private struct TabBar: View {
    @Binding var selectedTab: SettingsTab
    let language: AppLanguage

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(showsLabel: true)
            row(showsLabel: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func row(showsLabel: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                TabBarButton(
                    title: tab.title(language),
                    systemImage: tab.systemImage,
                    showsLabel: showsLabel,
                    isSelected: selectedTab == tab
                ) {
                    selectedTab = tab
                }
            }
        }
    }
}

private struct TabBarButton: View {
    let title: String
    let systemImage: String
    var showsLabel: Bool = true
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 16))
                if showsLabel {
                    Text(title)
                        .font(.caption)
                }
            }
            .frame(width: showsLabel ? 76 : 32)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            // `Color.clear` isn't hit-testable on its own, so without this the
            // button only responds where the icon/text glyphs are actually
            // drawn — not across the padded box around them, unlike a native
            // tab switcher.
            .contentShape(Rectangle())
        }
        // The icon-only row drops its only visible label, so both the
        // hover tooltip and VoiceOver's label fall back to the title text
        // that's still there, just not drawn.
        .help(showsLabel ? "" : title)
        .accessibilityLabel(title)
        .buttonStyle(.plain)
    }
}

// MARK: - Appearance

private struct AppearanceSettingsTab: View {
    @Binding var settings: AppSettings

    // Picked once when the tab appears — in the translation currently
    // selected in General — rather than inline in `body`: every settings
    // tweak (dragging a slider, moving a color picker) re-evaluates `body`,
    // and `VerseProvider.bundledRandom()` called there would reroll the
    // preview's verse on every single change instead of just once. Rerolled
    // explicitly, below, only when the translation itself changes, so the
    // preview actually reflects what the card will show rather than being
    // stuck in whatever translation happened to be picked at launch.
    @State private var previewVerse: Verse

    init(settings: Binding<AppSettings>) {
        _settings = settings
        _previewVerse = State(initialValue: VerseProvider.bundledRandom(enabledTranslations: [settings.wrappedValue.translationID]))
    }

    /// Small enough that the controls below still get most of the window, big
    /// enough for the card's proportions and a line or two of verse to read
    /// honestly.
    private let previewHeight: CGFloat = 132

    /// The preview sits outside the scrolling `Form` rather than in a section at
    /// the top of it, so it stays put while the settings scroll underneath —
    /// dragging Corner radius at the bottom of the list still shows the corners
    /// changing.
    private var language: AppLanguage { settings.language }

    var body: some View {
        VStack(spacing: 0) {
            preview
            Divider()
            Form {
                Section(language.t(.presets)) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(GradientTheme.presets) { preset in
                                ThemeSwatchButton(
                                    preset: preset,
                                    isSelected: settings.theme == preset.theme
                                ) {
                                    settings.theme = preset.theme
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section {
                    ColorPicker(
                        language.t(.startColor),
                        selection: Binding(
                            get: { settings.theme.startColor.color },
                            set: { settings.theme.startColor = RGBAColor($0) }
                        ),
                        supportsOpacity: false
                    )
                    ColorPicker(
                        language.t(.endColor),
                        selection: Binding(
                            get: { settings.theme.endColor.color },
                            set: { settings.theme.endColor = RGBAColor($0) }
                        ),
                        supportsOpacity: false
                    )
                    SliderSettingRow(label: language.t(.direction), value: $settings.theme.angle, range: 0...360, step: 1, suffix: "°")
                } header: {
                    Text(language.t(.gradient))
                } footer: {
                    Text(language.t(.gradientFooter))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(language.t(.textSectionHeader)) {
                    FontPicker(selection: $settings.font, language: language)
                    // Lives here rather than under Gradient: it's the colour of
                    // the text, and the thing it has to stay legible against is
                    // chosen two sections up either way.
                    ColorPicker(
                        language.t(.textColor),
                        selection: Binding(
                            get: { settings.theme.textColor.color },
                            set: { settings.theme.textColor = RGBAColor($0) }
                        ),
                        supportsOpacity: false
                    )
                }

                Section(language.t(.cardSectionHeader)) {
                    SliderSettingRow(label: language.t(.cornerRadius), value: $settings.cornerRadius, range: 0...40, step: 1)
                    SliderSettingRow(
                        label: language.t(.opacity),
                        // Opacity is stored 0.2...1.0 but shown/typed as a
                        // 20...100 percentage, so the conversion lives here
                        // rather than inside the row or field.
                        value: Binding<Double>(
                            get: { settings.opacity * 100 },
                            set: { settings.opacity = $0 / 100 }
                        ),
                        range: 20...100,
                        step: 1,
                        suffix: "%"
                    )
                    SliderSettingRow(label: language.t(.textSize), value: $settings.fontScale, range: 0.6...2.0, step: 0.1, decimals: 1, suffix: "×")
                }
            }
            .formStyle(.grouped)
        }
        .onChange(of: settings.translationID) { _, newID in
            previewVerse = VerseProvider.bundledRandom(enabledTranslations: [newID])
        }
    }

    /// The pinned header: a quiet title and the card itself.
    ///
    /// Drawn on `.bar` so the scrolling list reads as passing beneath it rather
    /// than being cut off by it.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language.t(.stylePreview))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VerseCardView(verse: previewVerse, settings: settings)
                .frame(height: previewHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

/// Picks between the four system designs and any installed font family.
///
/// Each family is drawn in its own typeface so the menu is browsable, and the
/// list comes from `NSFontManager.availableFontFamilies`. The app is the only
/// place that enumerates fonts — the widget just resolves whatever name it's
/// handed via `Font.custom`, falling back to the system font if the family
/// isn't there.
private struct FontPicker: View {
    @Binding var selection: FontChoice
    var language: AppLanguage = .en

    /// Enumerated once: the list runs to hundreds of families and doesn't change
    /// while Settings is open.
    private static let families: [String] = NSFontManager.shared
        .availableFontFamilies
        // Families beginning with "." are private system faces, not for users.
        .filter { !$0.hasPrefix(".") }
        .sorted()

    var body: some View {
        Picker(language.t(.font), selection: Binding<String>(
            get: { selection.storageValue },
            set: { selection = FontChoice(storageValue: $0) }
        )) {
            ForEach(FontChoice.SystemDesign.allCases) { design in
                Text(design.displayName)
                    .tag(FontChoice.system(design).storageValue)
            }

            Divider()

            ForEach(Self.families, id: \.self) { family in
                Text(family)
                    .font(.custom(family, size: 13))
                    .tag(family)
            }
        }
    }
}

private struct ThemeSwatchButton: View {
    let preset: ThemePreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(preset.theme.gradient)
                    .frame(width: 48, height: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                    )
                Text(preset.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 60)
    }
}

// MARK: - Size & Position

private struct SizePositionSettingsTab: View {
    @Binding var settings: AppSettings

    /// Matches the overlay panel's own minimum, so a value accepted here can't
    /// be silently overridden by the window's clamping.
    private static let minSide: Double = 150

    /// Used only if there's somehow no display to measure. Any real answer comes
    /// from `largestScreenSize()`.
    private static let fallbackMaxSide: Double = 6000

    private static let positionRange: ClosedRange<Double> = -20000...20000

    /// Bumped when the display arrangement changes. Nothing reads it — mutating
    /// state is what re-runs the body, which re-reads the screens below.
    @State private var screenChangeTick = 0

    /// The display the card is on, chosen the same way
    /// `OverlayWindowController.clampedFrame` chooses it.
    ///
    /// Everything screen-derived on this tab hangs off this one answer, because
    /// the two that used to disagree with it were both wrong in practice. The
    /// size fields took their maximum from the *largest* attached display while
    /// the panel clamps to the card's own, so on a laptop beside a big external
    /// monitor a width the field accepted was silently snapped down — the exact
    /// drift the field's limits existed to prevent. And the grid picker was built
    /// from the *main* display, so with the card on a secondary screen its cells
    /// described slots that were nowhere near where the card would land.
    private var cardScreen: NSScreen? {
        let frame = settings.overlayFrame
        return NSScreen.screens.first { $0.frame.intersects(frame) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    /// The usable area of that display — menu bar and Dock excluded, matching
    /// what the panel clamps against, so what's typed here is what's kept.
    private var maxCardSize: CGSize {
        cardScreen?.visibleFrame.size ?? CGSize(width: Self.fallbackMaxSide, height: Self.fallbackMaxSide)
    }

    private var grid: WidgetGrid? { WidgetGrid(screen: cardScreen) }

    private var widthRange: ClosedRange<Double> {
        Self.minSide...max(Self.minSide, maxCardSize.width)
    }

    private var heightRange: ClosedRange<Double> {
        Self.minSide...max(Self.minSide, maxCardSize.height)
    }

    private var language: AppLanguage { settings.language }

    var body: some View {
        Form {
            if let grid, WidgetGrid.isMeasuredSystem {
                Section {
                    WidgetGridPicker(settings: $settings, grid: grid)
                } header: {
                    Text(language.t(.placeOnWidgetGrid))
                } footer: {
                    Text(language.t(.widgetGridFooter) + (settings.overlayEnabled ? "" : language.t(.widgetGridFooterShowOverlayHint)) + ".")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Text(language.t(.widgetGridUnavailable))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                NumericSettingRow(
                    label: language.t(.width),
                    value: Binding<Double>(
                        get: { settings.overlayFrame.width },
                        set: { settings.overlayFrame.size.width = $0 }
                    ),
                    range: widthRange
                )
                NumericSettingRow(
                    label: language.t(.height),
                    value: Binding<Double>(
                        get: { settings.overlayFrame.height },
                        set: { settings.overlayFrame.size.height = $0 }
                    ),
                    range: heightRange
                )
            } header: {
                Text(language.t(.sizeSectionHeader))
            } footer: {
                Text(language.t(.sizeFooter, Int(Self.minSide)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                NumericSettingRow(
                    label: language.t(.xLabel),
                    value: Binding<Double>(
                        get: { settings.overlayFrame.origin.x },
                        set: { settings.overlayFrame.origin.x = $0 }
                    ),
                    range: Self.positionRange,
                    // Unlike size, these limits are just a sanity clamp rather
                    // than anything the screen dictates — printing "-20000–20000"
                    // next to a two-digit position would be noise.
                    showsBounds: false
                )
                NumericSettingRow(
                    label: language.t(.yLabel),
                    value: Binding<Double>(
                        get: { settings.overlayFrame.origin.y },
                        set: { settings.overlayFrame.origin.y = $0 }
                    ),
                    range: Self.positionRange,
                    showsBounds: false
                )
            } header: {
                Text(language.t(.positionSectionHeader))
            } footer: {
                Text(language.t(.positionFooter))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text(language.t(.unlockedHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        }
        .formStyle(.grouped)
        // Plugging in or unplugging a display changes what the card can fit
        // inside and where the widget slots fall, so the screen-derived limits
        // are re-read instead of going stale while the window stays open.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screenChangeTick += 1
        }
    }
}

/// Every settings row pins its control group to this height, so a row with a
/// slider in it and a row with only a value field come out identical rather than
/// each being as tall as whatever control it happens to hold.
private let settingRowHeight: CGFloat = 24

/// A full slider-backed setting row: label, the slider itself flanked by its
/// own min/max as small caption hints (so the range never has to be guessed
/// by dragging to the end), and an exact-value field with stepper.
///
/// Layout notes, since this row is fussier than it looks:
///
/// * The whole control group lives inside a single `LabeledContent`, not as
///   loose subviews of the row. Handing a grouped `Form` a multi-view `HStack`
///   lets it decide for itself which subviews are "label" and which are
///   "content", which is what used to strand the min hint way off at the left
///   of the row with a dead gap before the slider. One label, one content
///   view: the columns then line up with the `ColorPicker`/`Picker` rows.
/// * `hintWidth` is fixed and the value field group is `fixedSize`, so every
///   slider in a section starts and ends on the same x regardless of whether
///   its hints read "0" or "0.6×" — ragged track edges were the other half of
///   the mess.
/// * Everything is centered on one horizontal axis at the shared
///   `settingRowHeight`, so rows have identical heights instead of each one
///   being as tall as whatever control it happens to contain.
///
/// Operates entirely in "display units" — a caller whose underlying setting
/// isn't in the same units as what's shown (Opacity is stored 0.2...1.0 but
/// shown as 20...100%) passes a converting `Binding`, same as any other
/// SwiftUI control.
private struct SliderSettingRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var decimals: Int = 0
    var suffix: String = ""

    /// Wide enough for the longest hint any current row shows ("360°", "100%",
    /// "2.0×") at caption size.
    private let hintWidth: CGFloat = 32

    /// Below this much room for the track itself, a slider stops reading as
    /// a slider — its travel shrinks to a sliver and the thumb all but
    /// swallows it. `ViewThatFits` uses this as the horizontal layout's
    /// floor: narrower than this and `compactRow` takes over instead of the
    /// track getting crushed further.
    private let minTrackWidth: CGFloat = 120

    var body: some View {
        // Tries `wideRow` first; once the window is too narrow for it to fit
        // at `minTrackWidth`, falls back to `compactRow`. Both stay mounted
        // candidates rather than a manually-measured switch, so the row
        // reflows live as the window is dragged, not just on next open.
        ViewThatFits(in: .horizontal) {
            wideRow
            compactRow
        }
    }

    private var wideRow: some View {
        LabeledContent {
            HStack(alignment: .center, spacing: 8) {
                hint(range.lowerBound, alignment: .trailing)
                slider
                    .frame(minWidth: minTrackWidth)
                hint(range.upperBound, alignment: .leading)
                InlineNumericField(value: $value, range: range, decimals: decimals, step: step, suffix: suffix)
            }
            .frame(height: settingRowHeight)
        } label: {
            Text(label)
        }
    }

    /// The narrow-window fallback: label and exact-value field share a line,
    /// same as every other settings row, and the slider — with room to
    /// actually act like one — drops to its own line underneath.
    private var compactRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent {
                InlineNumericField(value: $value, range: range, decimals: decimals, step: step, suffix: suffix)
            } label: {
                Text(label)
            }
            HStack(alignment: .center, spacing: 8) {
                hint(range.lowerBound, alignment: .trailing)
                slider
                hint(range.upperBound, alignment: .leading)
            }
        }
    }

    private var slider: some View {
        // A slider given a `step:` draws a row of tiny tick marks under its
        // track — that faint dotted line. The snapping is worth keeping, the
        // dots aren't, so the rounding happens in the binding and the slider
        // itself stays smooth.
        Slider(
            value: Binding(
                get: { value },
                set: { value = Self.snap($0, to: step, in: range) }
            ),
            in: range
        )
        .controlSize(.small)
    }

    private func hint(_ bound: Double, alignment: Alignment) -> some View {
        Text(Self.format(bound, decimals: decimals) + suffix)
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.tertiary)
            .frame(width: hintWidth, alignment: alignment)
    }

    private static func snap(_ value: Double, to step: Double, in range: ClosedRange<Double>) -> Double {
        guard step > 0 else { return value }
        let stepped = (value / step).rounded() * step
        return min(max(stepped, range.lowerBound), range.upperBound)
    }

    private static func format(_ value: Double, decimals: Int) -> String {
        String(format: "%.\(decimals)f", value)
    }
}

/// `SliderSettingRow` without the slider: label, value field, stepper arrows.
///
/// For settings whose useful adjustments are smaller than a slider can express.
/// Size and position are the case in point — a track a couple of hundred points
/// long spanning a whole screen's width moves several pixels per pixel of mouse
/// travel, so "nudge it three to the left" is impossible on it, while the field
/// and the arrows do it exactly. Dragging the overlay itself covers the coarse
/// end that a slider would otherwise be good for.
///
/// Shares the field, stepper and row height with `SliderSettingRow` so the two
/// kinds of row line up wherever they appear together.
private struct NumericSettingRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var decimals: Int = 0
    var suffix: String = ""
    /// Wider than the Appearance rows' default: these numbers run to four
    /// digits, and negative positions to five.
    var fieldWidth: CGFloat = 62
    /// The accepted range, spelled out next to the field the way the slider rows
    /// spell theirs out at the ends of the track. Off for rows whose limits are
    /// arbitrary rather than meaningful.
    var showsBounds: Bool = true

    var body: some View {
        LabeledContent {
            HStack(alignment: .center, spacing: 8) {
                if showsBounds {
                    Text("\(Self.format(range.lowerBound, decimals: decimals))–\(Self.format(range.upperBound, decimals: decimals))\(suffix)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
                InlineNumericField(
                    value: $value,
                    range: range,
                    decimals: decimals,
                    step: step,
                    suffix: suffix,
                    fieldWidth: fieldWidth
                )
            }
            .frame(height: settingRowHeight)
        } label: {
            Text(label)
        }
    }

    private static func format(_ value: Double, decimals: Int) -> String {
        String(format: "%.\(decimals)f", value)
    }
}

/// The exact-value half of `SliderSettingRow`: a compact text field with a
/// stepper, showing the same value the slider controls.
///
/// Typing is committed only on Return or when focus leaves, never per
/// keystroke. A `TextField(value:format:)` writes through on every keystroke,
/// which made these fields unusable: each intermediate digit was published and
/// clamped, so typing "340" into a field with a 150 minimum went 3 → 150 → 15 →
/// 150…, reading as "my last digit vanished and the old value came back". The
/// in-progress text therefore lives in local state until commit.
///
/// Fractional input is rounded rather than discarded — typing "97.6" into a
/// whole-number field lands on 98. The stepper writes through immediately (a
/// click is already a deliberate, complete edit) and doubles as a second, more
/// discoverable way to find the row's bounds: it simply stops responding at
/// them. `IntField` below follows the same contract.
private struct InlineNumericField: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let decimals: Int
    let step: Double
    var suffix: String = ""
    var fieldWidth: CGFloat = 46
    var suffixWidth: CGFloat = 10

    @State private var text: String = ""
    /// The last text this field wrote for itself. Comparing against it tells
    /// "the user has typed something we haven't taken yet" apart from "the value
    /// changed elsewhere and we re-displayed it" — without that distinction,
    /// losing focus on an untouched field writes its stale contents back over
    /// whatever changed in the meantime.
    @State private var displayedText: String = ""
    @FocusState private var isFocused: Bool

    private var hasPendingEdit: Bool { text != displayedText }

    /// What the user can currently see, which is what the arrows must step from
    /// — typed-but-not-yet-committed text included.
    private var shownValue: Double {
        guard hasPendingEdit, let parsed = Double(text.trimmingCharacters(in: .whitespaces)) else { return value }
        return parsed
    }

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            // The system's bordered field, exactly as the Updates tab uses it,
            // rather than anything hand-drawn.
            //
            // Three attempts at a custom box all landed the digits low and
            // off-centre, for the same root reason each time: a text field's
            // height and baseline are its own business, and every trick for
            // overriding them — a background with padding, an explicit height, a
            // stack that centres it — fought that instead of using it. The
            // bordered style already centres its text properly and insets it from
            // the right edge, so the fix is to stop reinventing it.
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: fieldWidth)
                .focused($isFocused)
                .onSubmit(commit)
                .onChange(of: isFocused) { _, focused in
                    if !focused { commit() }
                }
                .onAppear { display(value) }
                .onChange(of: value) { _, newValue in
                    // Follow changes made elsewhere — the overlay being dragged,
                    // the grid picker, the arrows — but never clobber typing in
                    // progress. A focused field the user hasn't touched still
                    // follows along.
                    if !hasPendingEdit { display(newValue) }
                }
            Text(suffix)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: suffixWidth, alignment: .leading)
                .opacity(suffix.isEmpty ? 0 : 1)
            stepper
        }
        .fixedSize()
    }

    /// Hand-rolled rather than `Stepper(value:in:step:)`, which reads and writes
    /// the binding directly and so steps from the stored value while ignoring
    /// anything typed but not yet committed. That produced the wrong number
    /// twice over: click an arrow after typing "500" and it stepped 340 → 341,
    /// then losing focus committed the stale "500" on top — the new value
    /// appearing first and the old one landing after it.
    ///
    /// Stepping from what's on screen fixes both halves: the arrow takes the
    /// typed number as its starting point and writes the result straight to the
    /// field, which leaves nothing pending to be committed later.
    private var stepper: some View {
        Stepper(
            "",
            onIncrement: shownValue < range.upperBound ? { nudge(by: step) } : nil,
            onDecrement: shownValue > range.lowerBound ? { nudge(by: -step) } : nil
        )
        .labelsHidden()
        .controlSize(.small)
    }

    private func nudge(by delta: Double) {
        write(shownValue + delta)
    }

    private func commit() {
        // Nothing typed: re-display rather than write, so a focus change can't
        // resurrect an older number.
        guard hasPendingEdit else {
            display(value)
            return
        }
        guard let parsed = Double(text.trimmingCharacters(in: .whitespaces)) else {
            display(value) // unparseable: restore the live value
            return
        }
        write(parsed)
    }

    /// Rounds to the field's precision, clamps to its range, publishes, and
    /// re-displays — the single path by which this field changes anything.
    private func write(_ newValue: Double) {
        let rounded = Self.round(newValue, decimals: decimals)
        let clamped = min(max(rounded, range.lowerBound), range.upperBound)
        value = clamped
        display(clamped)
    }

    private func display(_ newValue: Double) {
        text = Self.format(newValue, decimals: decimals)
        displayedText = text
    }

    private static func round(_ value: Double, decimals: Int) -> Double {
        let factor = pow(10.0, Double(decimals))
        return (value * factor).rounded() / factor
    }

    private static func format(_ value: Double, decimals: Int) -> String {
        String(format: "%.\(decimals)f", value)
    }
}

/// The desktop widget grid on one display: where it starts, how big its cells
/// are, and how a span of cells maps to a card frame.
///
/// All of it follows from reading the real widget windows on macOS 26: each small
/// widget owns a 180×180 window, adjacent windows tile exactly 180 apart, the
/// first one starts 8 points in from the top-left of the space below the menu
/// bar, and the rounded card drawn inside each window is inset 9 points per side.
/// So cards are 162 across with 18 between them, and a card spanning `n` cells is
/// `n × 180 - 18`.
///
/// The anchor is derived from the screen rather than hardcoded at the measured
/// (8, 41): the 41 was the menu bar's 33 points plus the 8-point margin, and menu
/// bar height varies by display.
struct WidgetGrid {
    /// One widget cell, including the padding around its card.
    ///
    /// Not `private` (unlike the rest of this type) because
    /// `SettingsWindowController` also reads it, as the settings window's
    /// minimum resizable width.
    static let cell: Double = 180
    /// Padding between a cell's edge and the card drawn inside it.
    static let cardInset: Double = 9
    /// How far the first cell sits in from the corner of the usable screen area.
    static let margin: Double = 8
    /// Roughly what the system rounds widget cards by, used only for drawing.
    static let cardCornerRadius: Double = 18

    /// Whether these numbers were measured on the running system. They come from
    /// reading real widget windows on macOS 26 (Tahoe): each small widget owns a
    /// 180×180 window, adjacent windows tile exactly 180 apart, and the rounded
    /// card inside is inset 9 points per side — so cards are 162 across with 18
    /// between them, and a card spanning `n` cells is `n × 180 - 18`.
    ///
    /// Apple documents widget dimensions for iOS, iPadOS, visionOS and watchOS,
    /// but there is no Mac table, so measuring is the only way to know. Other
    /// versions therefore get no grid rather than Tahoe's numbers: these metrics
    /// have changed between releases before and would quietly be wrong.
    static var isMeasuredSystem: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26
    }

    /// Full display bounds and the part of it not under the menu bar or Dock,
    /// both in AppKit coordinates (origin bottom-left, y counting upward).
    let screenFrame: CGRect
    let visibleFrame: CGRect

    init?(screen: NSScreen?) {
        guard let screen else { return nil }
        screenFrame = screen.frame
        visibleFrame = screen.visibleFrame
    }

    static func cardSize(columns: Int, rows: Int) -> CGSize {
        CGSize(
            width: Double(columns) * cell - cardInset * 2,
            height: Double(rows) * cell - cardInset * 2
        )
    }

    /// Top-left corner of the first cell, measured downward from the top of the
    /// display the way the widgets themselves are laid out.
    var originFromTopLeft: CGPoint {
        let menuBarHeight = screenFrame.maxY - visibleFrame.maxY
        return CGPoint(x: visibleFrame.minX - screenFrame.minX + Self.margin, y: menuBarHeight + Self.margin)
    }

    var columns: Int { max(1, Int((visibleFrame.width - Self.margin) / Self.cell)) }
    var rows: Int { max(1, Int((visibleFrame.height - Self.margin) / Self.cell)) }

    /// The card frame for a rectangular span of cells, in the same AppKit
    /// coordinates `AppSettings.overlayFrame` uses.
    func cardFrame(columns columnRange: ClosedRange<Int>, rows rowRange: ClosedRange<Int>) -> CGRect {
        let size = Self.cardSize(columns: columnRange.count, rows: rowRange.count)
        let left = originFromTopLeft.x + Double(columnRange.lowerBound) * Self.cell + Self.cardInset
        let top = originFromTopLeft.y + Double(rowRange.lowerBound) * Self.cell + Self.cardInset
        return CGRect(
            x: screenFrame.minX + left,
            y: screenFrame.maxY - top - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// A cell's card rect measured from the top-left of the display, which is the
    /// space the picker draws in.
    func cardRectFromTopLeft(column: Int, row: Int) -> CGRect {
        CGRect(
            x: originFromTopLeft.x + Double(column) * Self.cell + Self.cardInset,
            y: originFromTopLeft.y + Double(row) * Self.cell + Self.cardInset,
            width: Self.cardSize(columns: 1, rows: 1).width,
            height: Self.cardSize(columns: 1, rows: 1).height
        )
    }

    /// Re-expresses a frame in AppKit coordinates as one measured from the
    /// display's top-left, which is the space the picker draws in.
    func rectFromTopLeft(_ frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX - screenFrame.minX,
            y: screenFrame.maxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    /// Which cell a point in top-left display coordinates falls in, clamped to
    /// the grid so a drag that runs off the edge still selects the last cell.
    func cell(at point: CGPoint) -> (column: Int, row: Int) {
        let column = Int(floor((point.x - originFromTopLeft.x) / Self.cell))
        let row = Int(floor((point.y - originFromTopLeft.y) / Self.cell))
        return (min(max(column, 0), columns - 1), min(max(row, 0), rows - 1))
    }
}

/// A miniature of the display, ruled into widget cells, that sets the card's
/// frame by dragging a rectangle across them.
///
/// Position and size are one gesture here rather than four numbers, because
/// that's how the intent actually arrives: "two cells wide, next to the clock",
/// not "342 by 162 at x=377". The numeric fields above stay for the cases the
/// grid can't express — a card between cells, or one deliberately off-grid.
///
/// The drag is deliberately stateless: both corners of the rectangle come from
/// the gesture's own `startLocation` and `location` every time it reports. An
/// earlier version remembered the anchor cell in `@State`, which broke whenever a
/// gesture ended without SwiftUI delivering `onEnded` — trackpad click-drags do
/// this — because the stale anchor then became one corner of the *next* drag's
/// rectangle. Deriving both corners from the gesture makes that impossible.
///
/// Writes happen live rather than on release, so the overlay walks the grid as
/// the drag moves and the result is visible before committing to it.
/// `lastWritten` keeps that to one write per rectangle rather than per mouse
/// point, and the drawn card is simply wherever the card now is — so what the
/// picker shows can't drift from what the setting says.
private struct WidgetGridPicker: View {
    @Binding var settings: AppSettings
    let grid: WidgetGrid

    @State private var lastWritten: CGRect?

    /// Keeps the miniature from eating the window on a tall display.
    private let maxHeight: CGFloat = 190

    var body: some View {
        Canvas { context, size in draw(in: context, size: size) }
            .aspectRatio(grid.screenFrame.width / grid.screenFrame.height, contentMode: .fit)
            .frame(maxHeight: maxHeight)
            .overlay {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(dragGesture(in: proxy.size))
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityLabel(settings.language.t(.widgetGridAccessibilityLabel))
            .accessibilityHint(settings.language.t(.widgetGridAccessibilityHint))
    }

    // MARK: Drawing

    private func draw(in context: GraphicsContext, size: CGSize) {
        let scale = size.width / grid.screenFrame.width

        context.fill(
            Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 6),
            with: .color(Color(nsColor: .underPageBackgroundColor))
        )

        // Empty cells, drawn with the widgets' own corner rounding so the grid
        // reads as widget slots rather than as a spreadsheet.
        for row in 0..<grid.rows {
            for column in 0..<grid.columns {
                let rect = scaled(grid.cardRectFromTopLeft(column: column, row: row), by: scale)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: WidgetGrid.cardCornerRadius * scale),
                    with: .color(.primary.opacity(0.08))
                )
            }
        }

        // The card itself: one filled shape spanning whatever cells it covers,
        // rather than the individual cells lit up separately — a card two cells
        // wide is one medium widget, and should look like one.
        let card = scaled(grid.rectFromTopLeft(settings.overlayFrame), by: scale)
        let cardPath = Path(roundedRect: card, cornerRadius: WidgetGrid.cardCornerRadius * scale)
        context.fill(cardPath, with: .color(.accentColor.opacity(0.55)))
        context.stroke(cardPath, with: .color(.accentColor), lineWidth: 1.5)
    }

    private func scaled(_ rect: CGRect, by scale: CGFloat) -> CGRect {
        CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
    }

    // MARK: Dragging

    private func dragGesture(in size: CGSize) -> some Gesture {
        // Zero minimum distance so a plain click selects a single cell — one
        // small widget is a perfectly reasonable thing to want.
        DragGesture(minimumDistance: 0)
            .onChanged { value in apply(value, in: size) }
            .onEnded { value in
                apply(value, in: size)
                lastWritten = nil
            }
    }

    private func apply(_ value: DragGesture.Value, in size: CGSize) {
        guard size.width > 0 else { return }
        let scale = grid.screenFrame.width / size.width
        let start = grid.cell(at: CGPoint(x: value.startLocation.x * scale, y: value.startLocation.y * scale))
        let end = grid.cell(at: CGPoint(x: value.location.x * scale, y: value.location.y * scale))
        let frame = grid.cardFrame(
            columns: min(start.column, end.column)...max(start.column, end.column),
            rows: min(start.row, end.row)...max(start.row, end.row)
        )
        guard frame != lastWritten else { return }
        lastWritten = frame
        settings.overlayFrame = frame
    }
}

// MARK: - Updates

private struct UpdatesSettingsTab: View {
    @Binding var settings: AppSettings

    private var language: AppLanguage { settings.language }

    var body: some View {
        Form {
            Section {
                // Type an exact value; the arrows are there for nudging, not as
                // the only way in. One control per row, since an HStack of two
                // inside a Form hoists the first child into the label slot.
                IntField(
                    label: language.t(.hours),
                    range: 0...24,
                    step: 1,
                    value: Binding<Int>(get: { hours }, set: { setHours($0) })
                )
                IntField(
                    label: language.t(.minutes),
                    range: 0...59,
                    step: 5,
                    value: Binding<Int>(get: { minutes }, set: { setMinutes($0) })
                )

            } header: {
                Text(language.t(.changeVerseEvery))
            } footer: {
                Text(language.t(.changeVerseEveryFooter, settings.widgetFrequency.displayName(language).lowercased()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(language.t(.quickPresets)) {
                HStack(spacing: 10) {
                    ForEach([15, 30, 60, 180, 720, 1440], id: \.self) { preset in
                        Button(label(forMinutes: preset)) {
                            settings.refreshMinutes = preset
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var hours: Int { settings.refreshMinutes / 60 }
    private var minutes: Int { settings.refreshMinutes % 60 }

    /// Both setters clamp the combined total into `refreshMinutesRange`, so the
    /// interval can never land on 0 (which would busy-loop the refresh timer)
    /// or exceed 24 hours.
    private func setHours(_ newHours: Int) {
        settings.refreshMinutes = clampTotal(newHours * 60 + minutes)
    }

    private func setMinutes(_ newMinutes: Int) {
        settings.refreshMinutes = clampTotal(hours * 60 + newMinutes)
    }

    private func clampTotal(_ total: Int) -> Int {
        min(max(total, AppSettings.refreshMinutesRange.lowerBound),
            AppSettings.refreshMinutesRange.upperBound)
    }

    private func label(forMinutes total: Int) -> String {
        let minutesShort = language.t(.minutesShort)
        let hoursShort = language.t(.hoursShort)
        switch total {
        case ..<60: return "\(total) \(minutesShort)"
        case 1440: return "24 \(hoursShort)"
        default:
            let h = total / 60
            let m = total % 60
            return m == 0 ? "\(h) \(hoursShort)" : "\(h) \(hoursShort) \(m) \(minutesShort)"
        }
    }
}

/// An editable integer field with stepper arrows alongside it.
///
/// Same commit-on-Return-or-blur contract as `InlineNumericField` (see the note
/// there on why per-keystroke writes are unusable), with the arrows writing
/// through immediately since a click is already a deliberate, complete edit.
private struct IntField: View {
    let label: String
    let range: ClosedRange<Int>
    let step: Int
    @Binding var value: Int

    @State private var text: String = ""
    /// See `InlineNumericField.displayedText` — same job, same reason.
    @State private var displayedText: String = ""
    @FocusState private var isFocused: Bool

    private var hasPendingEdit: Bool { text != displayedText }

    private var shownValue: Int {
        guard hasPendingEdit, let parsed = Double(text.trimmingCharacters(in: .whitespaces)) else { return value }
        return Int(parsed.rounded())
    }

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 8) {
                TextField("", text: $text)
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .focused($isFocused)
                    .onSubmit(commit)
                    .onChange(of: isFocused) { _, focused in
                        if !focused { commit() }
                    }
                    .onAppear { display(value) }
                    .onChange(of: value) { _, newValue in
                        // Reflect arrow clicks and any clamping the owner applied,
                        // but never overwrite an in-progress edit.
                        if !hasPendingEdit { display(newValue) }
                    }

                // Arrows step from what's displayed, including typed-but-not-yet
                // committed text, for the reasons spelled out on
                // `InlineNumericField.stepper`.
                Stepper(
                    "",
                    onIncrement: shownValue < range.upperBound ? { write(shownValue + step) } : nil,
                    onDecrement: shownValue > range.lowerBound ? { write(shownValue - step) } : nil
                )
                .labelsHidden()
            }
        }
    }

    private func commit() {
        guard hasPendingEdit else {
            display(value)
            return
        }
        // Parsed as Double first: a typed "17.6" should round to 18 rather
        // than being rejected outright just because `Int("17.6")` is nil.
        guard let parsed = Double(text.trimmingCharacters(in: .whitespaces)) else {
            display(value)
            return
        }
        write(Int(parsed.rounded()))
    }

    private func write(_ newValue: Int) {
        value = min(max(newValue, range.lowerBound), range.upperBound)
        // `value`'s owner may clamp further (e.g. forcing a non-zero total), so
        // re-read rather than echoing what we just wrote.
        display(value)
    }

    private func display(_ newValue: Int) {
        text = String(newValue)
        displayedText = text
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @Binding var settings: AppSettings
    var settingsStore = SettingsStore.shared

    /// Set right after the user changes `settings.language`, when a bundled
    /// translation exists in that language and the current translation isn't
    /// already it — cleared once the confirmation dialog is dismissed either
    /// way. See `handleLanguageChange`.
    @State private var suggestedTranslation: TranslationMeta?

    private var language: AppLanguage { settings.language }

    var body: some View {
        Form {
            Section {
                Picker(language.t(.languageLabel), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .onChange(of: settings.language) { _, newLanguage in
                    handleLanguageChange(to: newLanguage)
                }
            } header: {
                Text(language.t(.interfaceLanguageSectionHeader))
            }

            Section {
                Toggle(language.t(.showVerseOnDesktop), isOn: $settings.overlayEnabled)

                Toggle(language.t(.lockPosition), isOn: $settings.positionLocked)
                    .disabled(!settings.overlayEnabled)
                if !settings.overlayEnabled {
                    Text(language.t(.enableOverlayHint))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if settings.positionLocked {
                    Text(language.t(.lockedHint))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle(language.t(.showReferenceToggle), isOn: $settings.showReference)
                Text(language.t(.perWidgetReferenceHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                TranslationPickerView(selectedID: $settings.translationID, language: language)
            } header: {
                Text(language.t(.translationsSectionHeader))
            } footer: {
                Text(language.t(.translationsFooter))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !settingsStore.isShared {
                Section {
                    Label(
                        language.t(.widgetsNotSharedWarning),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            language.t(.switchTranslationTitle),
            isPresented: Binding(
                get: { suggestedTranslation != nil },
                set: { if !$0 { suggestedTranslation = nil } }
            ),
            presenting: suggestedTranslation
        ) { match in
            Button(language.t(.switchTranslationConfirm)) {
                settings.translationID = match.id
                suggestedTranslation = nil
            }
            Button(language.t(.switchTranslationKeep), role: .cancel) {
                suggestedTranslation = nil
            }
        } message: { match in
            Text(language.t(.switchTranslationMessage, language.displayName, match.displayName))
        }
    }

    /// Offers to switch the Bible translation to match a newly chosen
    /// interface language — but only when a bundled translation actually
    /// exists in that language and the current translation isn't already it,
    /// so the prompt never appears with nothing useful to suggest.
    private func handleLanguageChange(to newLanguage: AppLanguage) {
        guard let currentMeta = BundledTranslations.meta(id: settings.translationID),
              currentMeta.language != newLanguage.translationLanguageCode,
              let match = BundledTranslations.firstMeta(languageCode: newLanguage.translationLanguageCode)
        else { return }
        suggestedTranslation = match
    }
}

// MARK: - About

private struct AboutSettingsTab: View {
    let language: AppLanguage

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bibliada")
                        .font(.title3.weight(.semibold))
                    Text(language.t(.aboutTagline))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                Link(language.t(.aboutPrivacyPolicy), destination: URL(string: "https://walking-wisely.github.io/bibliada/privacy-policy.html")!)
                Link(language.t(.aboutSupport), destination: URL(string: "https://github.com/walking-wisely/bibliada/issues")!)
                Link(language.t(.aboutSourceCode), destination: URL(string: "https://github.com/walking-wisely/bibliada")!)
            }

            Section {
                Text(language.t(.aboutNotAffiliated))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(language.t(.aboutTranslationsCredit))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(language.t(.aboutAcknowledgementsSectionHeader))
            }

            Section {
                Text(language.t(.aboutAcknowledgement))
                    .font(.callout.weight(.medium))
            }
        }
        .formStyle(.grouped)
    }
}
