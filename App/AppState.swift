import Foundation
import AppKit
import Observation
import WidgetKit

/// Central app-level state: owns the current verse, the refresh timer, and
/// reacts to settings changes by re-arming the timer and driving the overlay
/// window controller. Lives for the lifetime of the process.
@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    /// The verse currently displayed in the menu bar / overlay.
    private(set) var verse: Verse

    /// Wall-clock time of the last successful refresh, used to detect how much
    /// time elapsed across sleep so we can catch up immediately on wake.
    private(set) var lastFetchDate: Date

    /// The sleep-and-fire loop driving scheduled (non-manual) refreshes. Kept
    /// separate from any manual-refresh task so a "New verse now" click can
    /// never accidentally cancel the recurring schedule.
    private var timerTask: Task<Void, Never>?
    /// A single in-flight manual/initial refresh, cancelled+replaced if the
    /// user mashes "New verse now" repeatedly.
    private var manualRefreshTask: Task<Void, Never>?
    private var overlayController: OverlayWindowController?
    private var settingsObservationTask: Task<Void, Never>?

    private init() {
        if let cached = VerseCache.load() {
            verse = cached.verse
            lastFetchDate = cached.fetchedAt
        } else {
            verse = VerseProvider.bundledRandom(enabledTranslations: Array(SettingsStore.shared.settings.enabledTranslationIDs))
            lastFetchDate = .distantPast
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    /// Call once from the app's `init` to start the refresh loop, perform the
    /// initial async refresh, and stand up the overlay if enabled.
    func start() {
        refreshNow()
        armTimer()
        applyOverlayState()
        observeSettings()
    }

    /// Manual "New verse now" action from the menu (also used for the very
    /// first refresh after launch, and to catch up after sleep/wake).
    func refreshNow() {
        manualRefreshTask?.cancel()
        manualRefreshTask = Task {
            await self.performRefresh()
        }
    }

    private func performRefresh() async {
        let next = await VerseProvider.shared.nextVerse(enabledTranslations: Array(SettingsStore.shared.settings.enabledTranslationIDs))
        guard !Task.isCancelled else { return }
        verse = next
        lastFetchDate = Date()
        overlayController?.applyVerseChange(next)
        WidgetCenter.shared.reloadTimelines(ofKind: "com.bibliada.verse-widget")
    }

    // MARK: - Timer

    /// Re-arms the interval timer to fire at `SettingsStore.shared.settings.frequency.interval`
    /// from now. We intentionally avoid a bare repeating `Timer`/`Task.sleep` loop as the sole
    /// mechanism: macOS suspends timers across sleep, so on wake we separately check elapsed
    /// time via `NSWorkspace.didWakeNotification` and catch up immediately if overdue.
    private func armTimer() {
        let interval = SettingsStore.shared.settings.refreshInterval
        timerTask?.cancel()
        timerTask = Task {
            do {
                try await Task.sleep(for: .seconds(interval))
            } catch {
                return // cancelled (e.g. settings changed, re-arming)
            }
            guard !Task.isCancelled else { return }
            await self.performRefresh()
            self.armTimer()
        }
    }

    @objc
    private func handleWake() {
        Task { @MainActor in
            let interval = SettingsStore.shared.settings.refreshInterval
            let elapsed = Date().timeIntervalSince(self.lastFetchDate)
            if elapsed >= interval {
                self.refreshNow()
            }
            // Whether or not we caught up, re-arm relative to "now" so the next
            // fire lands a full interval from the most recent refresh.
            self.armTimer()
        }
    }

    // MARK: - Settings reactivity

    /// Polls `SettingsStore.shared.settings` for changes relevant to this object
    /// (frequency, overlay enablement) since `@Observable` change notification is
    /// per-property-access rather than a Combine publisher we can subscribe to
    /// from a plain class outside SwiftUI's view body tracking.
    private func observeSettings() {
        settingsObservationTask?.cancel()
        var last = SettingsStore.shared.settings
        settingsObservationTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                let current = SettingsStore.shared.settings

                // Nothing changed: do no work at all. In particular, never touch
                // the overlay's frame on a tick where the user didn't edit it —
                // doing so fights an in-progress drag/resize and snaps the window
                // back to its stored position.
                guard current != last else { continue }

                let frequencyChanged = current.refreshMinutes != last.refreshMinutes
                let overlayEnabledChanged = current.overlayEnabled != last.overlayEnabled
                // Only reposition when the *stored* frame changed (i.e. the user
                // edited width/height in Settings). A frame written back by the
                // overlay itself after a drag also lands here, but then the
                // panel already has that frame, so the apply is a no-op.
                let frameChanged = current.overlayFrame != last.overlayFrame
                last = current

                if frequencyChanged {
                    self.armTimer()
                }
                if overlayEnabledChanged {
                    self.applyOverlayState()
                }
                // Live-apply theme/opacity/click-through edits to a visible overlay.
                self.overlayController?.applySettingsChange(current, applyFrame: frameChanged)
            }
        }
    }

    private func applyOverlayState() {
        let enabled = SettingsStore.shared.settings.overlayEnabled
        if enabled {
            if overlayController == nil {
                overlayController = OverlayWindowController()
            }
            overlayController?.show()
        } else {
            overlayController?.hide()
        }
    }
}
