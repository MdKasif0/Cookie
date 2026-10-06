import AppKit
import SpriteKit

/// SKView tuned for the desktop companion: accepts the first click even
/// when its panel has no keyboard focus, pauses rendering off screen,
/// and — crucially — only intercepts clicks that land on Cookie herself.
/// Transparent pixels pass through to whatever application is beneath,
/// so the panel never blocks the desktop around her.
final class CompanionSKView: SKView {
    private let hitTester: CookieHitTester?

    init(hitTester: CookieHitTester?) {
        self.hitTester = hitTester
        super.init(frame: NSRect(x: 0, y: 0, width: 180, height: 180))
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return super.hitTest(point) }
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if let hitTester, !hitTester.isOpaque(canvasPoint: local) {
            return nil
        }
        return super.hitTest(point) ?? self
    }

    private var occlusionObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
            self.occlusionObserver = nil
        }
        guard let window else {
            isPaused = true
            return
        }
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            self?.isPaused = !window.occlusionState.contains(.visible)
        }
    }
}

/// Hosts the SpriteKit scene inside the companion panel.
final class CompanionViewController: NSViewController {
    private let store: CookieStore
    private let behaviorEngine: CookieBehaviorEngine
    private let audioManager: AudioManager
    private let onPositionSettled: ((NSPoint) -> Void)?

    init(store: CookieStore,
         behaviorEngine: CookieBehaviorEngine,
         audioManager: AudioManager,
         onPositionSettled: ((NSPoint) -> Void)? = nil) {
        self.store = store
        self.behaviorEngine = behaviorEngine
        self.audioManager = audioManager
        self.onPositionSettled = onPositionSettled
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let skView = CompanionSKView(hitTester: CookieHitTester(canvasSize: CookieSpriteRenderer.canvasSize))
        skView.autoresizingMask = [.width, .height]
        skView.allowsTransparency = true
        let scene = CookieScene(
            size: skView.bounds.size,
            store: store,
            behaviorEngine: behaviorEngine,
            audioManager: audioManager,
            onPositionSettled: onPositionSettled
        )
        skView.presentScene(scene)
        view = skView
    }
}
