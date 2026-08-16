import SwiftUI

/// The rule table: the single source of truth for a pool's contents, and the
/// only view a user directly edits `pool.rules` through — the omnibar and
/// the discovery section (browser/search, Track 2) only ever append to it via
/// `PoolEditorView.addRules(_:isExclusion:)`.
///
/// Rows keep the array's own order rather than being sorted canonically.
/// Order is meaningful here — `VersePoolResolver.resolve` applies rules in
/// sequence, later ones winning — so resorting the table would silently
/// change what the pool selects out from under whoever built it.
struct PoolRuleTable: View {
    @Binding var pool: VersePool
    let translationID: String
    let language: AppLanguage
    var isReadOnly: Bool = false

    @State private var selection = Set<PoolRule.ID>()

    var body: some View {
        Group {
            if pool.rules.isEmpty {
                emptyState
            } else {
                table
            }
        }
    }

    private var emptyState: some View {
        Text(language.t(PoolLoc.ruleTableEmptyHint))
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
            .multilineTextAlignment(.center)
    }

    private var table: some View {
        Table(pool.rules, selection: $selection) {
            TableColumn(language.t(PoolLoc.ruleTableReferenceColumn)) { rule in
                Text(ReferenceParser.displayString(for: rule.range, translationID: translationID))
            }
            TableColumn(language.t(PoolLoc.ruleTableVersesColumn)) { rule in
                Text("\(VersePoolResolver.expand(rule.range).count)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            TableColumn(language.t(PoolLoc.ruleTableIncludeExcludeColumn)) { rule in
                includeExcludeControl(for: rule)
            }
        }
        // `Table` has no `List`-style `.onDelete`, but it's still an
        // NSResponder-backed view on macOS, so the standard delete-key
        // modifier reaches it the same way it would a `List`.
        .onDeleteCommand(perform: deleteCommand)
    }

    private var deleteCommand: (() -> Void)? {
        guard !isReadOnly else { return nil }
        return deleteSelected
    }

    private func includeExcludeControl(for rule: PoolRule) -> some View {
        Picker("", selection: binding(for: rule)) {
            Text(language.t(PoolLoc.ruleTableInclude)).tag(false)
            Text(language.t(PoolLoc.ruleTableExclude)).tag(true)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(width: 140)
        .disabled(isReadOnly)
    }

    /// A live binding into `pool.rules[index].isExclusion`, found by id since
    /// `Table` hands its row-content builder a value copy of the row, not an
    /// index into the backing array.
    private func binding(for rule: PoolRule) -> Binding<Bool> {
        guard let index = pool.rules.firstIndex(where: { $0.id == rule.id }) else {
            return .constant(rule.isExclusion)
        }
        return Binding(
            get: { pool.rules[index].isExclusion },
            set: { pool.rules[index].isExclusion = $0 }
        )
    }

    private func deleteSelected() {
        guard !isReadOnly, !selection.isEmpty else { return }
        pool.rules.removeAll { selection.contains($0.id) }
        selection.removeAll()
    }
}
