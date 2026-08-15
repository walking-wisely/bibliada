import AppKit
import SwiftUI

/// A multiselect combobox for choosing which bundled translations are active:
/// a fuzzy search field, a language filter, and a bounded-height list of rows
/// that support click, Cmd-click, Shift-click, and drag-to-select — the same
/// selection vocabulary as a Finder list.
///
/// Self-contained and stateless about persistence: the caller owns
/// `selectedIDs` (presumably `AppSettings.enabledTranslationIDs` or similar)
/// and this view only ever narrows or widens that set. It's meant to sit
/// inside a `Section` of some other `Form`, not to be one itself, so it draws
/// its own `LabeledContent`-style rows rather than a full `Form`.
struct TranslationPickerView: View {
    @Binding var selectedIDs: Set<String>

    @State private var query: String = ""
    @State private var languageFilter: String? = nil // nil = All

    /// The row last acted on by a click, kept for Shift-click range selection.
    /// Cleared implicitly whenever the filtered list no longer contains it —
    /// a Shift-click after the anchor has scrolled out of the current filter
    /// just falls back to toggling the clicked row alone.
    @State private var anchorID: String? = nil

    /// Rows the current drag has already applied selection to, so a drag that
    /// wobbles back and forth over the same row doesn't re-toggle it on every
    /// frame — see `dragGesture` below.
    @State private var dragTouchedIDs: Set<String> = []
    @State private var dragSelecting: Bool = true

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
            .filter { query.isEmpty || FuzzyMatch.matches(query: query, in: [$0.displayName, $0.languageName, $0.id]) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            controls
            rowList
            selectionButtons
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search translations", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 6)
            .frame(height: rowHeight)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary.opacity(0.4)))

            Picker("Language", selection: $languageFilter) {
                Text("All languages").tag(String?.none)
                ForEach(languages, id: \.self) { name in
                    Text(name).tag(String?.some(name))
                }
            }
            .labelsHidden()
            .frame(width: 150)
        }
    }

    // MARK: Row list

    private var rowList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filtered) { meta in
                    TranslationRow(
                        meta: meta,
                        isSelected: selectedIDs.contains(meta.id),
                        height: rowHeight
                    )
                    .contentShape(Rectangle())
                    .gesture(dragGesture(for: meta))
                }
                if filtered.isEmpty {
                    Text("No translations match “\(query)”.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
            }
            .padding(4)
        }
        .frame(height: listHeight)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.25)))
    }

    private var selectionButtons: some View {
        HStack {
            Button("Select All") { selectedIDs = Set(BundledTranslations.all.map(\.id)) }
            Button("Deselect All") { deselectAll() }
            Spacer()
            Text("\(selectedIDs.count) of \(BundledTranslations.all.count) selected")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Selection

    /// One `DragGesture` per row rather than one over the whole list, because a
    /// SwiftUI `List`/`LazyVStack` has no built-in notion of "which row is the
    /// pointer over right now" the way an `NSTableView` does. Each row's
    /// gesture only fires `onChanged` while the pointer is actually inside
    /// *that* row's bounds (SwiftUI still calls a view's gesture handlers as
    /// the drag crosses into it, even though the gesture started on a sibling
    /// view), so the combined effect across all rows is exactly "apply
    /// selection to every row the pointer passes over while the button is
    /// held" — a spreadsheet-style drag-select — without any manual hit
    /// testing or global mouse tracking.
    ///
    /// `minimumDistance: 0` so a plain click (no movement at all) still fires
    /// `onChanged`/`onEnded`, which is what click and Cmd/Shift-click ride on
    /// below — there's no separate `.onTapGesture`.
    private func dragGesture(for meta: TranslationMeta) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in handleTouch(meta) }
            .onEnded { _ in dragTouchedIDs = [] }
    }

    /// Called once per row per drag (guarded by `dragTouchedIDs`) as the
    /// pointer enters it, and also for a plain click since that's a
    /// zero-distance drag through the same row.
    private func handleTouch(_ meta: TranslationMeta) {
        guard !dragTouchedIDs.contains(meta.id) else { return }

        let isFirstTouchOfDrag = dragTouchedIDs.isEmpty
        dragTouchedIDs.insert(meta.id)

        if isFirstTouchOfDrag {
            // The row the drag/click started on decides the modifier-key
            // behavior for the whole gesture: a plain press-and-drag selects
            // everything it crosses (its own row included), Cmd toggles that
            // one row and the drag then extends the same "select" or
            // "deselect" action it started with, Shift does a one-shot range
            // select with no further drag semantics.
            let flags = NSEvent.modifierFlags
            if flags.contains(.shift), let anchorID, let anchorMeta = BundledTranslations.meta(id: anchorID) {
                selectRange(from: anchorMeta, to: meta)
                dragSelecting = true // irrelevant for range select, but keeps state consistent
            } else if flags.contains(.command) {
                let willSelect = !selectedIDs.contains(meta.id)
                setSelected(meta.id, willSelect)
                dragSelecting = willSelect
                anchorID = meta.id
            } else {
                let willSelect = !selectedIDs.contains(meta.id)
                setSelected(meta.id, willSelect)
                dragSelecting = willSelect
                anchorID = meta.id
            }
        } else {
            // Extending an existing drag: paint every row the pointer crosses
            // with whatever direction (select/deselect) the drag started with.
            setSelected(meta.id, dragSelecting)
        }
    }

    private func selectRange(from anchor: TranslationMeta, to target: TranslationMeta) {
        let ids = filtered.map(\.id)
        guard let anchorIndex = ids.firstIndex(of: anchor.id), let targetIndex = ids.firstIndex(of: target.id) else {
            setSelected(target.id, true)
            return
        }
        let range = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        for id in ids[range] {
            selectedIDs.insert(id)
        }
    }

    private func setSelected(_ id: String, _ selected: Bool) {
        if selected {
            selectedIDs.insert(id)
        } else if selectedIDs.count > 1 || !selectedIDs.contains(id) {
            // Never let a deselect empty the set — see `deselectAll` for the
            // same rule applied to the bulk button. Blocking the very last
            // remaining id here means a drag that sweeps across everything
            // simply stops removing once one is left, rather than emptying
            // the set mid-drag and relying on some later fixup.
            selectedIDs.remove(id)
        }
    }

    /// "Deselect All" would otherwise leave zero translations enabled, which
    /// has no sane fallback for verse selection — so it keeps exactly one:
    /// whichever was selected before (arbitrary but stable pick — the first
    /// bundled translation in the previous selection) if there was one, or
    /// the first bundled translation if the set was somehow already empty.
    private func deselectAll() {
        let keep = selectedIDs.first(where: { id in BundledTranslations.all.contains { $0.id == id } })
            ?? BundledTranslations.all.first?.id
        selectedIDs = keep.map { Set([$0]) } ?? []
    }
}

private struct TranslationRow: View {
    let meta: TranslationMeta
    let isSelected: Bool
    let height: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
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

// MARK: - Fuzzy matching

/// A deliberately simple subsequence matcher: `query`'s characters (lowercased)
/// must appear in order somewhere in the candidate, not necessarily adjacent —
/// "wb" matches "World English Bible" via the leading W and the B in "Bible".
/// No scoring/ranking is exposed since this picker only needs a yes/no filter,
/// not a sorted-by-relevance list.
enum FuzzyMatch {
    static func matches(query: String, in candidates: [String]) -> Bool {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return true }
        return candidates.contains { isSubsequence(needle, of: $0.lowercased()) }
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var needleIndex = needle.startIndex
        for char in haystack {
            guard needleIndex < needle.endIndex else { break }
            if char == needle[needleIndex] {
                needleIndex = needle.index(after: needleIndex)
            }
        }
        return needleIndex == needle.endIndex
    }
}

#Preview("Translation Picker") {
    TranslationPickerPreviewContainer()
        .padding()
        .frame(width: 480)
}

private struct TranslationPickerPreviewContainer: View {
    @State private var selected: Set<String> = ["WEB"]

    var body: some View {
        Form {
            Section("Translations") {
                TranslationPickerView(selectedIDs: $selected)
            }
        }
        .formStyle(.grouped)
    }
}
