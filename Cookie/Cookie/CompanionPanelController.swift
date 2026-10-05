import AppKit
import os

/// Cookie's home on the desktop: a transparent, focus-free floating panel
/// visible on every space. Clicking pets Cookie; dragging repositions her,
/// and the position is persisted.
@MainActor
final class CompanionPanelController: NSWindowController {
    static let panelSize = CGSize(width: 180, height: 180)

    private let store: CookieStore
    private var moveObserver: NSObjectProtocol?

    private let log = Logger(subsystem: "com.cookie.mac", category: "Windows")

    init(store: CookieStore, behaviorEngine: CookieBehaviorEngine, audioManager: AudioManager) {
        self.store = store
        let origin = store.profile.companionPosition.map { NSPoint(x: $0.x, y: $0.y) }
            ?? Self.defaultOrigin(size: Self.panelSize)
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
        panel.contentViewController = CompanionViewController(
            store: store,
            behaviorEngine: behaviorEngine,
            audioManager: audioManager
        )
        super.init(window: panel)

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let frame = self?.window?.frame else { return }
                self?.store.profile.companionPosition = CGPoint(x: frame.origin.x, y: frame.origin.y)
            }
        }
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        window?.orderFrontRegardless()
        log.debug("Companion panel shown")
    }

    func hide() {
        window?.orderOut(nil)
        log.debug("Companion panel hidden")
    }

    /// A friendly default spot: bottom center of the main screen.
    static func defaultOrigin(size: CGSize) -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }
        let visible = screen.visibleFrame
        return NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 96)
    }
}
