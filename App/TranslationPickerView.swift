import AppKit
import SwiftUI

/// A single-select combobox for choosing which bundled translation is active:
/// a language filter and a bounded-height list of rows where clicking a row
/// selects it — a plain radio-button list, one at a time.
///
/// Verse selection reads from exactly one translation. Letting more than one
/// be ticked at once (an earlier version did) meant the verse's *language*
/// changed at random between refreshes, which isn't a real choice so much as
/// an ungoverned one — this view makes that structurally impossible instead
/// of relying on a footer note to explain it.
///
/// Self-contained and stateless about persistence: the caller owns
/// `selectedID` (presumably `AppSettings.translationID`) and this view only
/// ever changes which single id it is. It's meant to sit inside a `Section`
/// of some other `Form`, not to be one itself, so it draws its own
/// `LabeledContent`-style rows rather than a full `Form`.
struct TranslationPickerView: View {
    @Binding var selectedID: String
    var language: AppLanguage = .en

    @State private var languageFilter: String? = nil // nil = All

    /// Every row's fixed height, matched to `settingRowHeight` in
    /// `SettingsView.swift` so this reads as one more control group in that
    /// same visual language rather than a foreign list widget.
    private let rowHeight: CGFloat = 24
    /// Caps the list at roughly 5 rows before it scrolls, so the 3 bundled
    /// translations today — and a few dozen down the road — never blow out
    /// the Settings window height the way an unbounded list would.
    private let listHeight: CGFloat = 160

    private var languages: [String] {
        // Distinct `languageName`s in first-seen order, not hardcoded and not
        // alphabetized — this way English (today's first-listed translation)
        // stays first in the filter menu rather than jumping around as
        // translations are added.
        var seen: Set<String> = []
        var result: [String] = []
        for meta in BundledTranslations.all where seen.insert(meta.languageName).inserted {
            result.append(meta.languageName)
        }
        return result
    }

    private var filtered: [TranslationMeta] {
        BundledTranslations.all
            .filter { languageFilter == nil || $0.languageName == languageFilter }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            controls
            rowList
        }
    }

    // MARK: Controls

    private var controls: some View {
        Picker(language.t(.allLanguages), selection: $languageFilter) {
            Text(language.t(.allLanguages)).tag(String?.none)
            ForEach(languages, id: \.self) { name in
                Text(name).tag(String?.some(name))
            }
        }
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Row list

    private var rowList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filtered) { meta in
                    TranslationRow(meta: meta, isSelected: selectedID == meta.id, height: rowHeight)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedID = meta.id }
                }
            }
            .padding(4)
        }
        .frame(height: listHeight)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.25)))
    }
}

private struct TranslationRow: View {
    let meta: TranslationMeta
    let isSelected: Bool
    let height: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
            VStack(alignment: .leading, spacing: 0) {
                Text(meta.displayName)
                    .font(.callout)
            }
            Spacer()
            Text(meta.languageName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : .clear)
        )
    }
}

#Preview("Translation Picker") {
    TranslationPickerPreviewContainer()
        .padding()
        .frame(width: 480)
}

private struct TranslationPickerPreviewContainer: View {
    @State private var selected: String = "WEB"

    var body: some View {
        Form {
            Section("Translations") {
                TranslationPickerView(selectedID: $selected)
            }
        }
        .formStyle(.grouped)
    }
}
