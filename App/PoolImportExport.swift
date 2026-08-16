import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The `.bibliadapool` document type, declared in code as well as in
/// `App/Info.plist`'s `UTExportedTypeDeclarations` (belt and suspenders: the
/// dynamic declaration here is what lets `NSOpenPanel`/`NSSavePanel` reason
/// about the type even if Launch Services hasn't re-scanned the Info.plist
/// yet, e.g. right after a debug build).
extension UTType {
    static let bibliadaPool = UTType(exportedAs: "com.bibliada.pool", conformingTo: .json)
}

/// One outcome of an import or export attempt — success with a report, or
/// one of several specific failures — as a single value so both the Verses
/// tab's inline alert and the double-click-to-open path (which has no
/// SwiftUI view to attach state to) can present the same information the
/// same way. Nothing that goes wrong, or gets silently skipped by a lesser
/// design, is left out of this: the point of validating on import is to
/// surface exactly what happened.
struct PoolIOAlert {
    let title: String
    let message: String?

    init(title: String, message: String? = nil) {
        self.title = title
        self.message = message
    }
}

/// An import attempt's alert plus, on success, the id of the pool that was
/// added to the store — so a caller with a selection to update (the Verses
/// tab list) can select what it just imported, while a caller with no such
/// concept (double-click-to-open) can ignore it.
struct PoolImportOutcome {
    let alert: PoolIOAlert
    let importedPoolID: UUID?
}

/// Save/open panel flows, pasteboard import, double-click-to-open, and error
/// presentation for pool interchange.
///
/// `interchangeControls` is the seam docs/verse-pool-contracts.md defines:
/// Track 1's `VersesSettingsTab` ships it as `EmptyView()` and, at merge,
/// calls straight through to `PoolImportExport.interchangeControls` in its
/// place.
@MainActor
enum PoolImportExport {
    @ViewBuilder
    static func interchangeControls(store: VersePoolStore, selection: Binding<UUID?>) -> some View {
        InterchangeControls(store: store, selection: selection)
    }

    // MARK: - Double-click / "Open With" entry point

    /// Called from `AppDelegate.application(_:openURLs:)` when the user
    /// double-clicks a `.bibliadapool` file or drops one on the app/Dock
    /// icon — the payoff of registering the document type in `Info.plist`.
    /// Runs the same import-and-validate path as the Verses tab's Import…
    /// button and presents the result as a standalone `NSAlert`, since at
    /// this point in the app's lifecycle there is no guarantee the Settings
    /// window (or any SwiftUI view) is even open to attach a report to.
    static func handleOpen(urls: [URL], store: VersePoolStore, settings: SettingsStore) {
        let language = settings.settings.language
        let translationID = settings.settings.translationID
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            let outcome: PoolImportOutcome
            if let data = try? Data(contentsOf: url) {
                let fallbackName = url.deletingPathExtension().lastPathComponent
                if url.pathExtension.lowercased() == "bibliadapool" {
                    outcome = importDocument(data: data, fallbackName: fallbackName, store: store, translationID: translationID, language: language)
                } else {
                    let text = String(data: data, encoding: .utf8) ?? ""
                    outcome = importPlainText(text, defaultName: fallbackName.isEmpty ? language.t(PoolIOLoc.importedPoolDefaultName) : fallbackName, store: store, translationID: translationID, language: language)
                }
            } else {
                outcome = PoolImportOutcome(alert: PoolIOAlert(title: language.t(PoolIOLoc.importFailedTitle), message: language.t(PoolIOLoc.errorUnreadable)), importedPoolID: nil)
            }
            present(outcome.alert, okTitle: language.t(PoolIOLoc.ok))
        }
    }

    private static func present(_ alert: PoolIOAlert, okTitle: String) {
        let nsAlert = NSAlert()
        nsAlert.messageText = alert.title
        if let message = alert.message { nsAlert.informativeText = message }
        nsAlert.addButton(withTitle: okTitle)
        nsAlert.runModal()
    }

    // MARK: - Shared import logic

    /// `.bibliadapool`, `.txt`, `.md`, and generic text — a `.md` UTType has
    /// to be looked up rather than referenced as a constant since
    /// `UniformTypeIdentifiers` has no built-in one for it.
    fileprivate static var importableTypes: [UTType] {
        var types: [UTType] = [.bibliadaPool, .plainText, .utf8PlainText, .text]
        if let markdown = UTType(filenameExtension: "md") { types.append(markdown) }
        return types
    }

    fileprivate static func importDocument(
        data: Data, fallbackName: String, store: VersePoolStore, translationID: String, language: AppLanguage
    ) -> PoolImportOutcome {
        let document: PoolDocument
        do {
            document = try PoolDocument.decode(from: data)
        } catch let error as PoolDocumentError {
            return PoolImportOutcome(alert: PoolIOAlert(title: language.t(PoolIOLoc.importFailedTitle), message: message(for: error, language: language)), importedPoolID: nil)
        } catch {
            return PoolImportOutcome(alert: PoolIOAlert(title: language.t(PoolIOLoc.importFailedTitle), message: language.t(PoolIOLoc.errorUnreadable)), importedPoolID: nil)
        }
        var pool = document.makePool()
        if pool.name.isEmpty { pool.name = fallbackName }
        return finishImport(pool: pool, lineFailures: [], store: store, translationID: translationID, language: language)
    }

    fileprivate static func importPlainText(
        _ text: String, defaultName: String, store: VersePoolStore, translationID: String, language: AppLanguage
    ) -> PoolImportOutcome {
        let result = PoolTextFormat.read(text)
        let rules = result.ranges.map { PoolRule(range: $0) }
        let pool = VersePool(name: defaultName, rules: rules)
        return finishImport(pool: pool, lineFailures: result.failures, store: store, translationID: translationID, language: language)
    }

    /// Common tail of both import paths: validate against the active
    /// translation, refuse an empty result (the design's guardrail — never
    /// save an empty pool), and otherwise commit it and report what was
    /// found, including anything that failed to parse or resolve. Nothing
    /// here drops a reference silently; every failure the caller collected
    /// ends up in the returned alert.
    fileprivate static func finishImport(
        pool: VersePool, lineFailures: [PoolTextFormat.LineFailure],
        store: VersePoolStore, translationID: String, language: AppLanguage
    ) -> PoolImportOutcome {
        let report = PoolValidationReport.validate(rules: pool.rules, translationID: translationID)
        guard !report.resolvesToNothing else {
            return PoolImportOutcome(alert: PoolIOAlert(
                title: language.t(PoolIOLoc.importRefusedEmptyTitle),
                message: language.t(PoolIOLoc.importRefusedEmptyMessage)
            ), importedPoolID: nil)
        }

        store.add(pool)

        var lines = [language.t(PoolIOLoc.importSucceededMessage, pool.name, report.verseCount)]
        if !report.missingInTranslation.isEmpty {
            lines.append("")
            lines.append(language.t(PoolIOLoc.importMissingInTranslation, report.missingInTranslation.count, translationID))
            lines.append(contentsOf: summarize(report.missingInTranslation.map {
                ReferenceParser.displayString(for: VerseRange($0), translationID: translationID)
            }))
        }
        if !lineFailures.isEmpty {
            lines.append("")
            lines.append(language.t(PoolIOLoc.importLinesFailed, lineFailures.count))
            lines.append(contentsOf: summarize(lineFailures.map { "line \($0.line): \($0.text)" }))
        }
        return PoolImportOutcome(
            alert: PoolIOAlert(title: language.t(PoolIOLoc.importSucceededTitle), message: lines.joined(separator: "\n")),
            importedPoolID: pool.id
        )
    }

    /// Caps a list shown inline in an alert at 12 lines, since a pool that's
    /// missing 400 references (a translation mismatch, say) shouldn't turn
    /// the dialog into an unscrollable wall of text — the count in the
    /// header line already says how many there are.
    private static func summarize(_ items: [String]) -> [String] {
        let cap = 12
        guard items.count > cap else { return items }
        return Array(items.prefix(cap)) + ["… and \(items.count - cap) more"]
    }

    private static func message(for error: PoolDocumentError, language: AppLanguage) -> String {
        switch error {
        case .notAnObject: return language.t(PoolIOLoc.errorNotAnObject)
        case .missingName: return language.t(PoolIOLoc.errorMissingName)
        case .missingRules: return language.t(PoolIOLoc.errorMissingRules)
        case .noRules: return language.t(PoolIOLoc.errorNoRules)
        case .invalidRange(let key): return language.t(PoolIOLoc.errorInvalidRange, key)
        }
    }
}

// MARK: - Controls

struct InterchangeControls: View {
    let store: VersePoolStore
    @Binding var selection: UUID?

    private var settingsStore = SettingsStore.shared
    @State private var alert: PoolIOAlert?

    /// Explicit, since the private `settingsStore`/`alert` properties above
    /// would otherwise make Swift's synthesized memberwise initializer
    /// private too — and `PoolImportExport.interchangeControls` (in the
    /// enclosing file, but a different type) needs to call this one.
    init(store: VersePoolStore, selection: Binding<UUID?>) {
        self.store = store
        self._selection = selection
    }

    private var language: AppLanguage { settingsStore.settings.language }
    private var translationID: String { settingsStore.settings.translationID }

    /// The pool `Export…` acts on: the one selected in the Verses tab list,
    /// falling back to curated so the button is never simply inert. Matches
    /// `VersePoolStore.activePool`'s own "never nothing" stance.
    private var exportCandidate: VersePool {
        store.pool(id: selection) ?? .curated
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(language.t(PoolIOLoc.importEllipsis)) {
                importFromFile()
            }
            Button(language.t(PoolIOLoc.importFromClipboard)) {
                importFromClipboard()
            }
            Menu(language.t(PoolIOLoc.exportEllipsis)) {
                Button(language.t(PoolIOLoc.exportFormatBibliadaPool)) {
                    exportPool(exportCandidate, as: .bibliadaPoolDocument)
                }
                Button(language.t(PoolIOLoc.exportFormatPlainText)) {
                    exportPool(exportCandidate, as: .plainText)
                }
            }
            // A `Menu` with a fixed label renders as a disclosure button
            // rather than a plain push button in some contexts; a
            // `menuStyle` keeps it visually in line with its two neighbors
            // instead of standing out as a different control.
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .alert(
            alert?.title ?? "",
            isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } }),
            presenting: alert
        ) { _ in
            Button(language.t(PoolIOLoc.ok)) { alert = nil }
        } message: { presentedAlert in
            if let message = presentedAlert.message { Text(message) }
        }
    }

    // MARK: - Import

    private func importFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = PoolImportExport.importableTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // NSOpenPanel hands back a security-scoped URL already authorized
        // for this access, no separate entitlement needed — but the
        // start/stop pair is still required to actually use it inside the
        // sandbox.
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            alert = PoolIOAlert(title: language.t(PoolIOLoc.importFailedTitle), message: language.t(PoolIOLoc.errorUnreadable))
            return
        }

        let suggestedName = url.deletingPathExtension().lastPathComponent
        let outcome: PoolImportOutcome
        if url.pathExtension.lowercased() == "bibliadapool" {
            outcome = PoolImportExport.importDocument(
                data: data, fallbackName: suggestedName, store: store, translationID: translationID, language: language
            )
        } else {
            let text = String(data: data, encoding: .utf8) ?? ""
            outcome = PoolImportExport.importPlainText(
                text,
                defaultName: suggestedName.isEmpty ? language.t(PoolIOLoc.importedPoolDefaultName) : suggestedName,
                store: store, translationID: translationID, language: language
            )
        }
        apply(outcome)
    }

    private func importFromClipboard() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        let outcome = PoolImportExport.importPlainText(
            text, defaultName: language.t(PoolIOLoc.pastedPoolDefaultName),
            store: store, translationID: translationID, language: language
        )
        apply(outcome)
    }

    /// Shows the outcome's alert and, on success, selects the newly imported
    /// pool in the Verses tab list — the one bit of UI state this file's
    /// static import logic can't reach on its own.
    private func apply(_ outcome: PoolImportOutcome) {
        alert = outcome.alert
        if let importedPoolID = outcome.importedPoolID {
            selection = importedPoolID
        }
    }

    // MARK: - Export

    private enum ExportFormat {
        case bibliadaPoolDocument
        case plainText
    }

    private func exportPool(_ pool: VersePool, as format: ExportFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = pool.name
        switch format {
        case .bibliadaPoolDocument:
            panel.allowedContentTypes = [.bibliadaPool]
            panel.nameFieldStringValue += ".bibliadapool"
        case .plainText:
            panel.allowedContentTypes = [.plainText]
            panel.nameFieldStringValue += ".txt"
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let data: Data?
        switch format {
        case .bibliadaPoolDocument:
            data = try? PoolDocument(pool: pool).encoded()
        case .plainText:
            let ranges = VersePoolResolver.resolve(rules: pool.rules).map(VerseRange.init)
            data = PoolTextFormat.write(ranges, translationID: translationID).data(using: .utf8)
        }
        guard let data else { return }
        try? data.write(to: url, options: .atomic)
    }
}
