import SwiftUI

/// The Verses settings tab: the list of pools (the built-in curated pool
/// first, a checkmark on whichever one selection currently draws from), and
/// the door into the standalone pool editor. See
/// `docs/verse-pool-customization.md`.
struct VersesSettingsTab: View {
    @Binding var settings: AppSettings
    private var store = VersePoolStore.shared

    init(settings: Binding<AppSettings>) {
        _settings = settings
    }

    /// The row highlighted in the list — independent of which pool is
    /// *active* (that's `settings.activePoolID`, shown with a checkmark).
    /// Selecting a row is what "Edit…", "Duplicate" and "Delete" act on.
    @State private var selectedPoolID: UUID?
    @State private var pendingDeleteID: UUID?
    /// Kept alive for as long as the tab is, so a window doesn't lose its
    /// only strong reference and close itself out from under the user.
    /// Windows are never pruned back out of this array on close — Settings is
    /// a lightweight singleton view, and holding on to a handful of stray
    /// controllers for windows the user has since closed by hand is a
    /// non-issue; wiring an `NSWindowDelegate` just to prune them isn't worth
    /// it here.
    @State private var openEditors: [PoolEditorWindowController] = []

    private var language: AppLanguage { settings.language }

    var body: some View {
        Form {
            Section {
                List(store.allPools, selection: $selectedPoolID) { pool in
                    row(for: pool)
                }
                .frame(minHeight: 180)
                .listStyle(.inset)

                HStack(spacing: 8) {
                    Button(language.t(PoolLoc.newPool), action: createPool)
                    Button(language.t(PoolLoc.duplicatePool), action: duplicateSelected)
                        .disabled(selectedPoolID == nil)
                    Button(language.t(PoolLoc.deletePool)) {
                        pendingDeleteID = selectedPoolID
                    }
                    .disabled(selectedPoolID == nil || isBuiltIn(selectedPoolID))
                    Spacer()
                    Self.interchangeControls(store: store, selection: $selectedPoolID)
                    Button(language.t(PoolLoc.editPoolEllipsis), action: editSelected)
                        .disabled(selectedPoolID == nil)
                }
            } header: {
                Text(language.t(PoolLoc.versesTabHeader))
            } footer: {
                Text(language.t(PoolLoc.versesTabFooter))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if selectedPoolID == nil {
                selectedPoolID = settings.activePoolID ?? VersePool.curatedID
            }
        }
        .confirmationDialog(
            language.t(PoolLoc.deletePoolConfirmTitle),
            isPresented: Binding(get: { pendingDeleteID != nil }, set: { if !$0 { pendingDeleteID = nil } })
        ) {
            Button(language.t(PoolLoc.deletePoolConfirmDelete), role: .destructive) {
                if let id = pendingDeleteID { deletePool(id: id) }
                pendingDeleteID = nil
            }
            Button(language.t(PoolLoc.deletePoolConfirmCancel), role: .cancel) {
                pendingDeleteID = nil
            }
        } message: {
            Text(language.t(PoolLoc.deletePoolConfirmMessage))
        }
    }

    private func row(for pool: VersePool) -> some View {
        HStack(spacing: 10) {
            Button {
                // Selection always goes through `activePoolID`, never a raw
                // write elsewhere — this *is* that write. `nil` for the
                // built-in pool matches `AppSettings.activePoolID`'s own
                // documented contract (nil means curated).
                settings.activePoolID = pool.isBuiltIn ? nil : pool.id
            } label: {
                Image(systemName: isActive(pool) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isActive(pool) ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(pool.isBuiltIn ? language.t(PoolLoc.curatedPoolName) : pool.name)
                Text(language.t(PoolLoc.poolVerseCount, VersePoolResolver.count(rules: pool.rules)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .tag(pool.id)
    }

    private func isActive(_ pool: VersePool) -> Bool {
        store.activePool(settings: settings).id == pool.id
    }

    private func isBuiltIn(_ id: UUID?) -> Bool {
        guard let id else { return false }
        return store.pool(id: id)?.isBuiltIn ?? false
    }

    private func createPool() {
        let pool = VersePool(name: language.t(PoolLoc.newPoolDefaultName), rules: [])
        store.add(pool)
        selectedPoolID = pool.id
    }

    private func duplicateSelected() {
        guard let id = selectedPoolID, let pool = store.pool(id: id) else { return }
        let copy = store.duplicate(pool)
        selectedPoolID = copy.id
    }

    private func deletePool(id: UUID) {
        guard !isBuiltIn(id) else { return }
        store.delete(id: id)
        // A deleted active pool degrades to curated, the same fallback
        // `VersePoolStore.activePool(settings:)` already applies elsewhere —
        // this just keeps the stored id from pointing at nothing.
        if settings.activePoolID == id { settings.activePoolID = nil }
        if selectedPoolID == id { selectedPoolID = nil }
    }

    private func editSelected() {
        guard let id = selectedPoolID else { return }
        let controller = PoolEditorWindowController(
            poolID: id, store: store, translationID: settings.translationID, language: language
        )
        openEditors.append(controller)
        controller.show()
    }

    /// Filled in by the import/export track — the Import…/Export… buttons.
    @ViewBuilder
    static func interchangeControls(store: VersePoolStore, selection: Binding<UUID?>) -> some View {
        EmptyView()
    }
}
