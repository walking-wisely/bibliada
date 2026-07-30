import AppKit
import SwiftUI

/// A borderless `NSPanel` that hosts `VerseCardView` pinned at desktop level,
/// behind normal app windows but above the desktop icons/wallpaper. This is the
/// "fake widget" / desktop overlay described in SPEC.md: it supports arbitrary
/// rectangular sizes and drag-resizing, unlike the real WidgetKit widget which
/// is limited to fixed system sizes.
@MainActor
final class OverlayWindowController: NSObject, NSWindowDelegate {
    private let panel: OverlayPanel
    private let hostingView: NSHostingView<OverlayCardView>
    private var frameSaveWorkItem: DispatchWorkItem?

    /// True only while a settings-driven frame is being pushed into the panel, so
    /// the resulting move/resize notifications aren't mistaken for the user
    /// moving the window. See `applySettingsChange`.
    private var isApplyingStoredFrame = false
    /// `nonisolated(unsafe)` so `deinit` (which is not main-actor isolated) can
    /// unregister them. Only ever mutated on the main actor during setup, and
    /// read once at teardown when no other reference to `self` survives.
    private nonisolated(unsafe) var spaceObservers: [NSObjectProtocol] = []

    /// Whether the user has the overlay switched on at all.
    private var isVisibleBySetting = false

    /// Whether Mission Control / Exposé / Launchpad is currently covering the
    /// desktop, in which case the card fades out even though it's switched on.
    private var isSuppressedByExpose = false {
        didSet {
            guard oldValue != isSuppressedByExpose else { return }
            updateEffectiveVisibility(animated: true)
        }
    }

    override init() {
        let settings = SettingsStore.shared.settings
        let verse = AppState.shared.verse

        let initialFrame = Self.clampedFrame(settings.overlayFrame, forFrameOf: nil)

        let card = OverlayCardView(verse: verse, settings: settings)
        let hosting = NSHostingView(rootView: card)
        hostingView = hosting

        // `.borderless` + `.resizable`: no titlebar chrome to fight the card's own
        // rounded corners, but the resizable style mask is what lets AppKit install
        // edge-drag resize handles even though there's no visible frame.
        let newPanel = OverlayPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel = newPanel

        super.init()

        configurePanel()
        panel.contentView = hostingView
        panel.setFrame(initialFrame, display: false)
        panel.delegate = self
        panel.overlayController = self

        observeMissionControl()
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for observer in spaceObservers {
            center.removeObserver(observer)
        }
    }

    // MARK: - Panel configuration

    private func configurePanel() {
        // Fully transparent chrome: the card itself draws its own rounded rect,
        // background, and shadow, so the window must contribute none of its own.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true

        // Desktop-icon level + 1: sits directly above the Finder desktop icons /
        // wallpaper but below every ordinary app window (which start at
        // `.normal`, well above this). We verified empirically that using
        // `.desktopIconWindow + 1` (rather than `.normalWindow - 1`, which some
        // window levels treat as clamped to `.normalWindow`) reliably stays
        // beneath Finder windows and every regular app window across Spaces.
        let level = Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
        panel.level = NSWindow.Level(rawValue: level)

        // `.canJoinAllSpaces` so the card is present on every desktop, including
        // ones created after launch — matching how real desktop widgets
        // replicate. Deliberately WITHOUT `.stationary`: that flag lifts the
        // window above the Space-switch animation, which is what made the card
        // visibly float across sliding desktops.
        //
        // `.moveToActiveSpace` was tried instead and is wrong here — it binds
        // the window to a single Space, so a newly created desktop shows
        // nothing at all until you switch to it.
        //
        // The remaining transition artifact is handled by fading the card out
        // during Mission Control / Exposé rather than by window flags.
        //
        // Keep it out of Mission Control's window list, Cmd-Tab (the App
        // Switcher), and the Dock/Windows menu, since this is decorative
        // desktop chrome, not a real window the user switches to.
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]
        panel.isExcludedFromWindowsMenu = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none

        // Non-activating panel: clicking/dragging it must not steal key focus
        // from whatever app the user is actually working in, or bring our own
        // (invisible) menu-bar-only app to the foreground.
        panel.becomesKeyOnlyIfNeeded = true
        panel.worksWhenModal = false

        // Mouse handling is decided by the position lock; see
        // `applyPositionLock`.
        panel.ignoresMouseEvents = false
    }

    // MARK: - Show/hide

    func show() {
        applyPositionLock(SettingsStore.shared.settings.positionLocked)
        isVisibleBySetting = true
        panel.orderBack(nil)
        updateEffectiveVisibility(animated: false)
    }

    func hide() {
        isVisibleBySetting = false
        panel.orderOut(nil)
    }

    // MARK: - Mission Control / Exposé

    /// macOS exposes no public API for "Mission Control is up". The reliable,
    /// permission-free proxy is that invoking Mission Control, App Exposé, or
    /// Launchpad activates the Dock (`com.apple.dock`) as the frontmost
    /// application, and dismissing it activates something else. Real desktop
    /// widgets fade out for the duration, so we mirror that.
    ///
    /// This is a heuristic, not a guarantee: it also fires when the user simply
    /// clicks a Dock item, which fades the card briefly. That's a deliberate
    /// trade-off — a stray fade is far less jarring than the card hanging over
    /// Mission Control.
    private func observeMissionControl() {
        let center = NSWorkspace.shared.notificationCenter

        spaceObservers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            let isDock = app?.bundleIdentifier == "com.apple.dock"
            MainActor.assumeIsolated {
                self?.isSuppressedByExpose = isDock
            }
        })

        // A completed Space switch means whatever was covering the desktop is
        // gone, so make sure we're not left stuck hidden.
        //
        // Deliberately does NOT re-fade the card in. This notification fires
        // *after* the switch animation, so forcing alpha to 0 and animating back
        // up reads as a flicker on arrival, not as a graceful appearance. And
        // there's nothing to mask: because the panel is on all Spaces at a fixed
        // position, the outgoing and incoming desktops both show the card in the
        // same place, exactly like per-desktop widgets do.
        spaceObservers.append(center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isSuppressedByExpose = false
            }
        })
    }

    private func updateEffectiveVisibility(animated: Bool) {
        let shouldShow = isVisibleBySetting && !isSuppressedByExpose
        let target: CGFloat = shouldShow ? 1 : 0
        guard panel.alphaValue != target else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = shouldShow ? 0.25 : 0.12
                panel.animator().alphaValue = target
            }
        } else {
            panel.alphaValue = target
        }
    }

    // MARK: - Live settings updates

    /// Called by `AppState` when settings actually changed, so appearance and
    /// click-through edits made in Settings apply live.
    ///
    /// `applyFrame` must only be true when the *stored* frame changed (a size
    /// edit in Settings). The panel's own position is authoritative while the
    /// user is dragging or live-resizing it: pushing a stored frame in on a
    /// timer would snap the window out from under the cursor mid-drag.
    func applySettingsChange(_ settings: AppSettings, applyFrame: Bool) {
        hostingView.rootView = OverlayCardView(verse: AppState.shared.verse, settings: settings)
        applyPositionLock(settings.positionLocked)

        guard applyFrame, !panel.isUserInteracting, !panel.inLiveResize else { return }
        let stored = Self.clampedFrame(settings.overlayFrame, forFrameOf: panel.screen)
        if panel.frame != stored {
            // Applying a stored frame makes the panel post move/resize
            // notifications, and persisting those would write the frame we were
            // just handed straight back into settings. Harmless when settings
            // change one at a time; actively wrong when they arrive in a stream,
            // as they do while dragging the widget-grid picker: the debounced
            // save would fire after the drag ended, carrying whichever
            // intermediate frame the panel had reached, and overwrite the final
            // one. Anything pending is stale by definition once a newer stored
            // frame arrives, so it's dropped too.
            isApplyingStoredFrame = true
            frameSaveWorkItem?.cancel()
            frameSaveWorkItem = nil
            panel.setFrame(stored, display: true)
            DispatchQueue.main.async { [weak self] in
                self?.isApplyingStoredFrame = false
            }
        }
    }

    /// Refreshes the card's verse without touching frame/appearance.
    func applyVerseChange(_ verse: Verse) {
        hostingView.rootView = OverlayCardView(verse: verse, settings: SettingsStore.shared.settings)
    }

    /// Locking the card is implemented by having the panel ignore mouse events
    /// outright: nothing can drag or resize what doesn't receive the drag, and
    /// clicks land on whatever is behind it, which is what you want from
    /// something meant to sit there like wallpaper.
    ///
    /// The side effect worth remembering: this also disables the card's own
    /// right-click menu, so the unlock has to come from the menu-bar menu or
    /// Settings.
    private func applyPositionLock(_ locked: Bool) {
        panel.ignoresMouseEvents = locked
    }

    // MARK: - Frame persistence

    /// Debounces frame writes so rapid drag-resize events don't spam
    /// `SettingsStore` (which persists synchronously on every `didSet`).
    private func scheduleFrameSave() {
        frameSaveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.persistFrameNow()
        }
        frameSaveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Writes the panel's current frame straight into settings, cancelling any
    /// pending debounced save. Called on drag/resize end.
    func persistFrameNow() {
        frameSaveWorkItem?.cancel()
        frameSaveWorkItem = nil
        let frame = panel.frame
        guard SettingsStore.shared.settings.overlayFrame != frame else { return }
        var settings = SettingsStore.shared.settings
        settings.overlayFrame = frame
        SettingsStore.shared.settings = settings
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        guard !isApplyingStoredFrame else { return }
        scheduleFrameSave()
    }

    func windowDidResize(_ notification: Notification) {
        guard !isApplyingStoredFrame else { return }
        scheduleFrameSave()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        persistFrameNow()
    }

    func windowDidChangeScreen(_ notification: Notification) {
        let clamped = Self.clampedFrame(panel.frame, forFrameOf: panel.screen)
        if clamped != panel.frame {
            panel.setFrame(clamped, display: true)
            scheduleFrameSave()
        }
    }

    // MARK: - Screen clamping

    /// Clamps `frame` to lie within the visible frame of the nearest screen,
    /// handling the case where the stored frame is off-screen entirely (e.g.
    /// an external display was disconnected since last launch) or the display
    /// configuration otherwise changed.
    private static func clampedFrame(_ frame: CGRect, forFrameOf screen: NSScreen?) -> CGRect {
        let targetScreen = screen
            ?? NSScreen.screens.first { $0.frame.intersects(frame) }
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let visible = targetScreen?.visibleFrame else {
            return frame
        }

        var size = frame.size
        size.width = min(max(size.width, 150), visible.width)
        size.height = min(max(size.height, 150), visible.height)

        var origin = frame.origin
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)

        return CGRect(origin: origin, size: size)
    }
}

/// `NSPanel` subclass that:
/// - accepts key events despite being a non-activating borderless panel, so
///   that (when click-through is off) drag/resize interactions work normally;
/// - tracks whether an interactive drag/resize is in progress so programmatic
///   settings-driven frame updates don't fight the user mid-gesture.
private final class OverlayPanel: NSPanel {
    weak var overlayController: OverlayWindowController?

    /// True for the whole duration of a user drag or edge-resize.
    ///
    /// `isMovableByWindowBackground` drags run inside a nested event-tracking
    /// loop within `super.mouseDown(with:)`, which does not return until the
    /// mouse comes back up. Main-queue work (including `AppState`'s settings
    /// poll) is still serviced during that loop, so this flag is what keeps a
    /// concurrent frame apply from stealing the window mid-drag.
    private(set) var isUserInteracting = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func mouseDown(with event: NSEvent) {
        isUserInteracting = true
        super.mouseDown(with: event)
        isUserInteracting = false
        // The drag/resize has finished and the panel's frame is authoritative —
        // persist it right away rather than waiting out the debounce, so a poll
        // tick can never observe a stale stored frame.
        overlayController?.persistFrameNow()
    }
}
