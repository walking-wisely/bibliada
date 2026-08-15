import SwiftUI
import AppKit

/// Bibliada is a menu-bar-only app (`LSUIElement` in Info.plist, owned by
/// Agent 2) — there is no Dock icon and no default window. All UI is reached
/// through the menu-bar status item or the `Settings` scene opened from it.
@main
struct BibliadaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // `App` conformances are `@MainActor`-isolated, so this is safe to call
        // directly. Runs exactly once per process launch.
        AppState.shared.start()
    }

    var body: some Scene {
        // Both the status item/popover and the Settings window are plain
        // AppKit, owned by `MenuBarController` — not `MenuBarExtra` and
        // `Settings`. `MenuBarExtra` only wires up left-click to open its
        // window, with no public hook to also open it on right-click; and
        // once the app manages its own `NSApplicationDelegate`, the
        // `Settings` scene's `showSettingsWindow:` action turned out not to
        // be reliably reachable either — tried activating first, tried
        // deferring the send past the popover's own close, neither helped.
        // A `Scene` still has to be declared to satisfy `App`, so this one is
        // intentionally inert — `Settings` rather than `WindowGroup` because
        // it's the one kind that never auto-opens a window at launch.
        Settings {
            EmptyView()
        }
    }
}

/// Owns the `NSStatusItem` that `MenuBarExtra` would otherwise manage, purely
/// so `applicationDidFinishLaunching` has a place to create `MenuBarController`
/// at the right point in the app lifecycle.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController()
    }
}
