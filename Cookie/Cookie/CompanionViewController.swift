import AppKit
import SpriteKit

/// SKView that accepts the first click even when its panel has no keyboard
/// focus (so petting Cookie never needs a warm-up click) and pauses
/// rendering whenever the panel is off screen, keeping a hidden companion
/// essentially free.
final class CompanionSKView: SKView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
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

    init(store: CookieStore, behaviorEngine: CookieBehaviorEngine, audioManager: AudioManager) {
        self.store = store
        self.behaviorEngine = behaviorEngine
        self.audioManager = audioManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let skView = CompanionSKView(frame: NSRect(x: 0, y: 0, width: 180, height: 180))
        skView.autoresizingMask = [.width, .height]
        skView.allowsTransparency = true
        let scene = CookieScene(
            size: skView.bounds.size,
            store: store,
            behaviorEngine: behaviorEngine,
            audioManager: audioManager
        )
        skView.presentScene(scene)
        view = skView
    }
}
