import AppKit
import os

/// Cookie's home on the desktop: a transparent, focus-free floating panel
/// visible on every space. Clicks land only on Cookie's silhouette; the
/// rest of the panel passes events through to the apps beneath. Dragging
/// repositions her, the position persists, and screen changes (display
/// plugged, unplugged, resolution change) can never strand her off screen.
@MainActor
final class CompanionPanelController: NSWindowController {
    static let panelSize = CGSize(width: 180, height: 180)

    private let store: CookieStore
    private var screenObservers: [NSObjectProtocol] = []

    private let log = Logger(subsystem: "com.cookie.mac", category: "Windows")

    init(store: CookieStore, behaviorEngine: CookieBehaviorEngine, audioManager: AudioManager) {
        self.store = store
        let origin = CookieScreenGeometry.restoreOrigin(
            saved: store.profile.companionPosition,
            size: Self.panelSize,
            screens: NSScreen.screens
        )
        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        panel.contentViewController = CompanionViewController(
            store: store,
            behaviorEngine: behaviorEngine,
            audioManager: audioManager,
            onPositionSettled: { [weak self] _ in
                self?.savePosition()
            }
        )

        let center = NotificationCenter.default
        screenObservers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.recoverVisiblePosition()
            }
        })
        screenObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.recoverVisiblePosition()
            }
        })
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        screenObservers.forEach(NotificationCenter.default.removeObserver)
    }

    func show() {
        window?.orderFrontRegardless()
        log.debug("Companion panel shown")
    }

    func hide() {
        window?.orderOut(nil)
        log.debug("Companion panel hidden")
    }

    /// Persists the current panel origin to the store.
    func savePosition() {
        guard let origin = window?.frame.origin else { return }
        store.profile.companionPosition = CGPoint(x: origin.x, y: origin.y)
    }

    /// After displays change, make sure Cookie is still reachable.
    func recoverVisiblePosition() {
        guard let window else { return }
        let safe = CookieScreenGeometry.safeOrigin(for: window.frame, in: NSScreen.screens)
        if safe != window.frame.origin {
            window.setFrameOrigin(safe)
            log.info("Repositioned companion into the visible area after a display change")
        }
        savePosition()
    }
}
