import SwiftUI

/// The verse card as the desktop overlay presents it: the shared `VerseCardView`
/// plus a right-click menu.
///
/// The menu exists mainly for locking. Once the card is where you want it, the
/// natural gesture is to right-click the thing itself and say "stay there" —
/// going to Settings to protect a position you just set by dragging is a detour.
///
/// Unlocking, though, can never live only here: a locked card ignores the mouse,
/// which includes the right-click that would open this menu. So the same toggle
/// is in the menu-bar menu and in Settings, and those are the ways back.
struct OverlayCardView: View {
    let verse: Verse
    let settings: AppSettings

    var body: some View {
        VerseCardView(verse: verse, settings: settings)
            .contextMenu {
                Toggle("Lock position", isOn: Self.positionLockedBinding)
                Button("New verse now") {
                    AppState.shared.refreshNow()
                }
            }
    }

    /// Reads and writes the live store rather than a passed-in binding: this view
    /// is handed to an `NSHostingView` and rebuilt whenever settings change, so a
    /// captured binding would be a snapshot.
    static var positionLockedBinding: Binding<Bool> {
        Binding(
            get: { SettingsStore.shared.settings.positionLocked },
            set: { newValue in
                var settings = SettingsStore.shared.settings
                settings.positionLocked = newValue
                SettingsStore.shared.settings = settings
            }
        )
    }
}
