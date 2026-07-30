import SwiftUI
import AppKit

/// Bibliada is a menu-bar-only app (`LSUIElement` in Info.plist, owned by
/// Agent 2) — there is no Dock icon and no default window. All UI is reached
/// through the `MenuBarExtra` or the `Settings` scene opened from it.
@main
struct BibliadaApp: App {
    init() {
        // `App` conformances are `@MainActor`-isolated, so this is safe to call
        // directly. Runs exactly once per process launch.
        AppState.shared.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
        } label: {
            Image(systemName: "book.closed")
        }
        // `.window` style (rather than `.menu`) is required so the popover can
        // host an arbitrary SwiftUI view (the mini verse card) instead of being
        // limited to plain menu items.
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

/// The content of the menu-bar popover: a small live verse preview plus the
/// handful of actions/toggles the SPEC calls for.
private struct MenuBarContentView: View {
    @Environment(\.openSettings) private var openSettings
    private var appState = AppState.shared
    private var settingsStore = SettingsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VerseCardView(verse: appState.verse, settings: settingsStore.settings)
                .frame(width: 260, height: 180)

            Button("New verse now") {
                appState.refreshNow()
            }
            .keyboardShortcut("n", modifiers: [.command])

            Toggle("Show verse on desktop", isOn: overlayEnabledBinding)

            // Also on the card's own right-click menu, but that one goes away
            // while the card is locked — this is the way back.
            Toggle("Lock position", isOn: OverlayCardView.positionLockedBinding)
                .disabled(!settingsStore.settings.overlayEnabled)

            Divider()

            Button("Settings…") {
                openSettingsWindow()
            }
            .keyboardShortcut(",", modifiers: [.command])

            Button("Quit") {
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

    /// Menu-bar-only (`LSUIElement`) apps don't reliably surface `Settings`
    /// windows unless the app is first activated — otherwise the window can
    /// open behind other apps or not visibly come forward at all. Activating
    /// before invoking the `openSettings` environment action is the reliable
    /// combination on macOS 15+.
    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }
}
