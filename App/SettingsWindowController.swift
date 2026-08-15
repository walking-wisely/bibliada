import SwiftUI
import AppKit

/// Owns the Settings window, created lazily on first open and reused (rather
/// than recreated) on every subsequent one, so its position and size stay put
/// between visits — the same behavior SwiftUI's `Settings` scene gives for
/// free.
///
/// This is hand-rolled AppKit instead of that `Settings` scene because the
/// scene's `showSettingsWindow:` action isn't reliably reachable once the app
/// manages its own `NSApplicationDelegate` and menu-bar popover by hand (see
/// `MenuBarController`) rather than going through SwiftUI's own
/// app-lifecycle scaffolding — sending that selector from here, even
/// deferred a run-loop turn past activation and past closing the popover,
/// was confirmed a no-op. A window we own and show ourselves has no such
/// dependency. The cost is that `SettingsView`'s `TabView` loses macOS's
/// native icon-and-label tab switcher, which only appears inside a real
/// `Settings` scene — `SettingsView` hand-rolls a matching one instead of
/// relying on that.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    /// Name under which the window's frame is saved to and restored from
    /// `UserDefaults`, so its size and position survive a full app relaunch
    /// too, not just a close/reopen within one run (which the reused window
    /// instance already gives for free — see the type doc above).
    private static let frameAutosaveName = "SettingsWindow"

    /// `NSWindow.minSize`/`contentMinSize` are set to this below, but aren't
    /// trusted to still hold once the window is on screen: logging a live
    /// resize showed both reset to AppKit's own defaults — `(0, 32)`, i.e.
    /// "no minimum, just the titlebar" — sometime between window creation
    /// and the user's first drag, most likely by `NSHostingController`'s
    /// first layout pass despite `sizingOptions` being turned off. So
    /// `windowWillResize(_:to:)` below clamps by hand against this constant
    /// instead of trusting whatever `sender.minSize` reads at drag time.
    private static let minWindowSize = NSSize(width: 300, height: 500)

    convenience init() {
        let hostingController = NSHostingController(rootView: SettingsView())
        // Default sizing options resize the window to match SwiftUI's
        // intrinsic content size on every layout pass, which fights a user
        // drag on the resize edge. `SettingsView`'s own `.frame` already
        // states the min/ideal/max sizes that matter, so the window is left
        // to size itself from those and from the user's own drags instead.
        hostingController.sizingOptions = []
        let window = NSWindow(contentViewController: hostingController)
        window.title = SettingsStore.shared.settings.language.t(.settingsWindowTitle)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        // Set for whatever native behavior (e.g. double-clicking the zoom
        // button) still consults them, even though the actual floor is
        // enforced by `windowWillResize(_:to:)` — see `minWindowSize`.
        window.minSize = Self.minWindowSize
        window.contentMinSize = Self.minWindowSize
        // With `sizingOptions` above turned off, the hosting controller no
        // longer sizes the window to its content itself — so without this
        // the window opens at whatever size `NSWindow` starts with, which is
        // effectively zero. This gives it the same size the fixed `.frame`
        // used to, before it became the resizable min/ideal/max one.
        window.setContentSize(NSSize(width: 520, height: 560))
        // The window is reused rather than torn down on close, so it must
        // survive its own `close()` instead of deallocating with it.
        window.isReleasedWhenClosed = false
        // Restores a previously saved frame if there is one; falls back to
        // the default size, centered, if it's the first time the window is
        // ever opened, or if an earlier, buggy build of this controller
        // saved a degenerate (near-zero) frame before a minimum existed to
        // prevent that.
        let restored = window.setFrameUsingName(Self.frameAutosaveName)
        if !restored || window.frame.width < Self.minWindowSize.width || window.frame.height < Self.minWindowSize.height {
            window.setContentSize(NSSize(width: 520, height: 560))
            window.center()
        }
        window.setFrameAutosaveName(Self.frameAutosaveName)
        self.init(window: window)
        window.delegate = self
    }

    /// The actual floor on a user's resize drag — see `minWindowSize` for why
    /// this, rather than `NSWindow.minSize`, is what's authoritative.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(
            width: max(frameSize.width, Self.minWindowSize.width),
            height: max(frameSize.height, Self.minWindowSize.height)
        )
    }

    func show() {
        window?.title = SettingsStore.shared.settings.language.t(.settingsWindowTitle)
        // Menu-bar-only (`LSUIElement`) apps don't reliably surface ordinary
        // windows unless the app is first activated — otherwise the window
        // can open behind other apps or not visibly come forward at all.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
