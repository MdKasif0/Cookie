import SpriteKit
import Combine
import os

/// The scene behind the desktop companion (and the small preview views).
/// It renders whatever `SpriteProviding` character it is given, mirrors
/// appearance changes from the store, and forwards mouse interaction to
/// the behavior engine. Click pets Cookie; dragging moves the panel.
final class CookieScene: SKScene {
    private let character: CookieCharacterNode
    private let store: CookieStore?
    private let behaviorEngine: CookieBehaviorEngine?
    private let audioManager: AudioManager?
    private var cancellables: Set<AnyCancellable> = []
    private var dragDistance: CGFloat = 0

    private let log = Logger(subsystem: "com.cookie.mac", category: "Scene")

    init(size: CGSize,
         store: CookieStore? = nil,
         behaviorEngine: CookieBehaviorEngine? = nil,
         audioManager: AudioManager? = nil) {
        self.store = store
        self.behaviorEngine = behaviorEngine
        self.audioManager = audioManager
        let appearance = store?.profile.appearance ?? .classicCream
        character = CookieCharacterNode(palette: .standard(for: appearance))
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        character.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(character)
        character.startIdling()
        bindObservers()
    }

    required init?(coder: NSCoder) { nil }

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        log.debug("Scene presented at \(Int(self.size.width), privacy: .public)×\(Int(self.size.height), privacy: .public)")
    }

    /// Used by preview views that have no store binding of their own.
    func applyAppearance(_ appearance: CookieAppearance) {
        character.apply(palette: .standard(for: appearance))
    }

    private func bindObservers() {
        guard let store else { return }

        store.$profile
            .map(\.appearance)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] appearance in
                self?.character.apply(palette: .standard(for: appearance))
            }
            .store(in: &cancellables)

        if let behaviorEngine {
            behaviorEngine.$activity
                .receive(on: DispatchQueue.main)
                .sink { [weak self] activity in
                    self?.character.setActivity(activity)
                }
                .store(in: &cancellables)
        }
    }

    // MARK: - Interaction

    override func mouseDown(with event: NSEvent) {
        dragDistance = 0
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = view?.window else { return }
        let origin = window.frame.origin
        window.setFrameOrigin(NSPoint(x: origin.x + event.deltaX, y: origin.y + event.deltaY))
        dragDistance += abs(event.deltaX) + abs(event.deltaY)
    }

    override func mouseUp(with event: NSEvent) {
        // A drag moved the panel; a click pets Cookie.
        guard dragDistance < 4 else { return }
        behaviorEngine?.registerPet()
        audioManager?.play(.pet)
    }
}
