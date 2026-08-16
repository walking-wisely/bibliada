import AppKit
import SwiftUI

/// Opens the pool editor in its own resizable window — never inline in
/// Settings and never a sheet over it. The Settings window is deliberately
/// compact and fixed-feeling (see `SettingsWindowController`), while the
/// editor needs room for a rule table today and, once Track 2 lands, a
/// three-column browser and search results alongside it. This is the
/// standard macOS shape for "edit one item's details" next to a compact
/// list — Mail keeps its rule list in Preferences and opens each rule's
/// conditions in its own window; Font collections do the same.
///
/// Unlike `SettingsWindowController`, this controller is not reused: each
/// call opens a fresh window bound to one pool, the same way Mail opens a
/// separate window per rule rather than recycling a single one across
/// different rules. Opening the same pool twice therefore opens two windows
/// onto the same underlying data — an accepted, minor rough edge rather than
/// machinery to track and refocus a single window per pool id.
@MainActor
final class PoolEditorWindowController: NSWindowController {
    private static let defaultSize = NSSize(width: 900, height: 560)
    private static let minSize = NSSize(width: 640, height: 420)

    convenience init(poolID: UUID, store: VersePoolStore, translationID: String, language: AppLanguage) {
        let binding = Binding<VersePool>(
            get: { store.pool(id: poolID) ?? .curated },
            set: { store.update($0) }
        )
        let hostingController = NSHostingController(
            rootView: PoolEditorView(pool: binding, translationID: translationID, language: language)
        )
        // Same reasoning as `SettingsWindowController`: default sizing
        // options resize the window to match SwiftUI's intrinsic content size
        // on every layout pass, fighting a user drag on the resize edge. The
        // view's own `.frame` already states the min/ideal/max sizes that
        // matter.
        hostingController.sizingOptions = []
        let window = NSWindow(contentViewController: hostingController)
        let pool = store.pool(id: poolID)
        window.title = pool.map { $0.isBuiltIn ? language.t(PoolLoc.curatedPoolName) : $0.name }
            ?? language.t(PoolLoc.poolEditorWindowTitle)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.minSize = Self.minSize
        window.contentMinSize = Self.minSize
        // Without `sizingOptions` above, the hosting controller no longer
        // sizes the window to its content itself, so without this the window
        // opens at whatever size a bare `NSWindow` starts at (effectively
        // zero) — see `SettingsWindowController.init` for the same fix.
        window.setContentSize(Self.defaultSize)
        window.center()
        self.init(window: window)
    }

    /// Brings the window frontmost even though the app runs `.accessory`
    /// (menu-bar-only, no Dock icon). Unlike `SettingsWindowController.show`,
    /// this doesn't itself flip the app's activation policy to `.regular` —
    /// the only way to reach the pool editor is through the Verses tab of an
    /// already-open Settings window, which has already made that switch and
    /// will revert it when it closes. Duplicating the switch here would mean
    /// two controllers racing to set the same global policy back and forth as
    /// each window closes independently.
    func show() {
        NSApp.activate()
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}
