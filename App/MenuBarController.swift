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
        //
        // Deferred a run-loop turn (plus a short delay) rather than called
        // synchronously here: this whole initializer runs inside
        // `applicationDidFinishLaunching`, and calling
        // `NSApp.setActivationPolicy`/`activate()` that early — before the OS
        // has finished registering the launch with the window server — was
        // observed to silently no-op. `SettingsWindowController.show()`
        // still creates the window either way, just left behind every other
        // app on screen with no way to tell it happened.
        if isFirstLaunch {
            UserDefaults.standard.set(true, forKey: Self.hasLaunchedBeforeKey)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.openSettings() }
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
        // normally. `activate()` (no `ignoringOtherApps:`) is the non-deprecated
        // macOS 14+ replacement; this call site is always in response to a real
        // click on the status item, so — unlike the auto-opened Settings window
        // on first launch — cooperative activation reliably grants it without
        // needing `orderFrontRegardless()` too.
        NSApp.activate()
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
    private var poolStore = VersePoolStore.shared

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

            addToPoolMenu
            Button(language.t(PoolBrowserLoc.menuExcludeThisVerse)) {
                excludeCurrentVerse()
            }
            .disabled(excludeTargetPool == nil)

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

    /// "Add current verse to ▸ [pool]" — one item per user-created pool. The
    /// built-in curated pool never appears here: `VersePoolStore.append` is a
    /// no-op for it (see `VersePoolStore.update`), so offering it would
    /// silently do nothing.
    @ViewBuilder
    private var addToPoolMenu: some View {
        Menu(language.t(PoolBrowserLoc.menuAddCurrentVerseTo)) {
            if poolStore.pools.isEmpty {
                Text(language.t(PoolBrowserLoc.menuNoPoolsYet))
            } else {
                ForEach(poolStore.pools) { pool in
                    Button(pool.name) {
                        addCurrentVerse(toPoolWithID: pool.id)
                    }
                }
            }
        }
    }

    /// The pool "Exclude this verse" writes into: the active pool, but only
    /// when it's user-created — the curated one can be active with no pool
    /// selected yet, and it can't be mutated, so the item disables instead of
    /// silently doing nothing.
    private var excludeTargetPool: VersePool? {
        let pool = poolStore.activePool(settings: settingsStore.settings)
        return pool.isBuiltIn ? nil : pool
    }

    /// `appState.verse.reference` is a display string ("John 3:16"), not a
    /// canonical `VerseReference` — reparsing it through `ReferenceParser`
    /// reuses the one parser that already knows every bundled translation's
    /// book names, rather than teaching this view its own book-name lookup.
    private func currentRange() -> VerseRange? {
        ReferenceParser.parseOne(appState.verse.reference)
    }

    private func addCurrentVerse(toPoolWithID id: UUID) {
        guard let range = currentRange() else { return }
        poolStore.append(rule: PoolRule(range: range), toPoolWithID: id)
    }

    private func excludeCurrentVerse() {
        guard let pool = excludeTargetPool, let range = currentRange() else { return }
        poolStore.append(rule: PoolRule(range: range, isExclusion: true), toPoolWithID: pool.id)
    }
}
