import SwiftUI
import AppKit

/// Manages the menu-bar status item and its popover directly with AppKit.
///
/// This exists instead of SwiftUI's `MenuBarExtra` because `MenuBarExtra` only
/// opens its window on a primary (left) click — there's no public API to make
/// a right-click do the same thing. An `NSStatusItem` button, by contrast,
/// lets us route both click types to one action via `sendAction(on:)`.
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let hostingController: NSHostingController<MenuBarContentView>
    private let settingsWindowController: SettingsWindowController

    /// Fixed width the popover content is laid out at — `sizeThatFits`, below,
    /// measures the height that results from it.
    private static let contentWidth: CGFloat = 288

    /// Set once the very first time the app ever launches — checked and
    /// flipped in `init` below, ahead of the on-launch Settings prompt, so a
    /// relaunch never shows it again.
    private static let hasLaunchedBeforeKey = "hasLaunchedBefore"

    override init() {
        let isFirstLaunch = !UserDefaults.standard.bool(forKey: Self.hasLaunchedBeforeKey)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        popover = NSPopover()
        hostingController = NSHostingController(rootView: MenuBarContentView(openSettings: {}))
        settingsWindowController = SettingsWindowController(initialTab: isFirstLaunch ? .about : .appearance)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "book.closed", accessibilityDescription: "Bibliada")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(togglePopover(_:))
            // Left AND right click both open/close the popover — the whole
            // point of dropping `MenuBarExtra` for this controller.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // `openSettings` closes over `self`, so it's wired up here rather than
        // at construction above, once `self` exists.
        hostingController.rootView = MenuBarContentView(openSettings: { [weak self] in self?.openSettings() })

        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = hostingController

        // First launch ever: an `LSUIElement` app with no Dock icon and no
        // window otherwise gives a first-time user nothing to look at beyond
        // a small menu-bar glyph they have to already know to look for — see
        // the discovery problem in docs/publishing/CHECKLIST.md §6. Opening
        // Settings straight to About answers it without waiting for the user
        // to find the icon on their own.
        if isFirstLaunch {
            UserDefaults.standard.set(true, forKey: Self.hasLaunchedBeforeKey)
            openSettings()
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        guard let button = statusItem.button else { return }
        // As an `LSUIElement` app, we're never the active app, so without this
        // the popover shows without ever becoming key: it mispositions itself
        // and `.transient` dismissal doesn't work on the first outside click,
        // since there's no key window to resign. Activating first — the same
        // fix `SettingsWindowController.show()` needs — makes both behave
        // normally.
        NSApp.activate(ignoringOtherApps: true)
        // Measured explicitly and set *before* `show()`, rather than left to
        // `NSHostingController`'s own automatic (but here unreliable —
        // sometimes under, sometimes over) sizing: an under-measurement just
        // silently clips the popover's content with no scrollbar to reveal
        // the rest, and an over/late measurement animates a resize after the
        // popover is already on screen, which previously showed up as the
        // whole popover drifting up over the menu bar mid-appearance.
        // Measuring once, synchronously, up front avoids both.
        popover.contentSize = hostingController.sizeThatFits(
            in: CGSize(width: Self.contentWidth, height: .greatestFiniteMagnitude)
        )
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func openSettings() {
        popover.performClose(nil)
        settingsWindowController.show()
    }
}

/// The content of the menu-bar popover: a small live verse preview plus the
/// handful of actions/toggles the SPEC calls for.
private struct MenuBarContentView: View {
    let openSettings: () -> Void

    private var appState = AppState.shared
    private var settingsStore = SettingsStore.shared

    // The synthesized memberwise init would be `private` here (it touches the
    // `private` `appState`/`settingsStore` properties), which even within
    // this file is scoped to this struct's own declaration — not visible from
    // `MenuBarController`, which constructs this view. Spelling it out avoids
    // that.
    init(openSettings: @escaping () -> Void) {
        self.openSettings = openSettings
    }

    private var language: AppLanguage { settingsStore.settings.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VerseCardView(verse: appState.verse, settings: settingsStore.settings)
                .frame(width: 260, height: 180)

            Button(language.t(.newVerseNow)) {
                appState.refreshNow()
            }
            .keyboardShortcut("n", modifiers: [.command])

            Toggle(language.t(.showVerseOnDesktop), isOn: overlayEnabledBinding)

            // Also on the card's own right-click menu, but that one goes away
            // while the card is locked — this is the way back.
            Toggle(language.t(.lockPosition), isOn: OverlayCardView.positionLockedBinding)
                .disabled(!settingsStore.settings.overlayEnabled)

            Divider()

            Button(language.t(.settingsEllipsis)) {
                openSettings()
            }
            .keyboardShortcut(",", modifiers: [.command])

            Button(language.t(.quit)) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
        .padding(14)
        .frame(width: 288)
    }

    private var overlayEnabledBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.overlayEnabled },
            set: {
                var updated = settingsStore.settings
                updated.overlayEnabled = $0
                settingsStore.settings = updated
            }
        )
    }
}
