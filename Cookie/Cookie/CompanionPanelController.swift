import AppKit
import os

/// Cookie's home on the desktop: a transparent, focus-free floating panel
/// visible on every space. Clicks land only on Cookie's silhouette; the
/// rest of the panel passes events through to the apps beneath. Dragging
/// repositions her, the position persists, and screen changes (display
/// plugged, unplugged, resolution change) can never strand her off screen.
@MainActor
final class CompanionPanelController: NSWindowController {
    /// Base size; the Settings "Cookie size" slider scales the panel.
    static let baseSize = CGSize(width: CookieScreenGeometry.basePanelDimension,
                                 height: CookieScreenGeometry.basePanelDimension)

    private let store: CookieStore
    private var screenObservers: [NSObjectProtocol] = []

    private let log = Logger(subsystem: "com.cookie.mac", category: "Windows")

    var panelSize: CGSize {
        CGSize(width: Self.baseSize.width * store.profile.settings.cookieSize,
               height: Self.baseSize.height * store.profile.settings.cookieSize)
    }

    init(store: CookieStore, behaviorEngine: CookieBehaviorEngine, audioManager: AudioManager) {
        self.store = store
        let size = CGSize(width: Self.baseSize.width * store.profile.settings.cookieSize,
                          height: Self.baseSize.height * store.profile.settings.cookieSize)
        let saved = store.profile.settings.rememberPosition ? store.profile.companionPosition : nil
        let origin = CookieScreenGeometry.restoreOrigin(
            saved: saved,
            size: size,
            screens: NSScreen.screens
        )
        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
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

    /// Persists the current panel origin to the store (honoring the
    /// "Remember position" setting).
    func savePosition() {
        guard store.profile.settings.rememberPosition,
              let origin = window?.frame.origin else { return }
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
