import SpriteKit
import Combine
import os

/// The scene behind the desktop companion (and the small preview views).
/// It renders whatever `SpriteProviding` character it is given, mirrors
/// appearance changes from the store, forwards mouse interaction to the
/// behavior engine, and — while Cookie is in a walking activity — glides
/// the companion panel across the desktop, respecting screen edges.
/// Click pets Cookie; dragging picks her up and moves the panel.
final class CookieScene: SKScene {
    private let character: CookieCharacterNode
    private let store: CookieStore?
    private let behaviorEngine: CookieBehaviorEngine?
    private let audioManager: AudioManager?
    /// Invoked whenever Cookie's position settles: after a drop, at the
    /// end of a walk, or when she stops at a screen edge.
    private let onPositionSettled: ((NSPoint) -> Void)?
    private var cancellables: Set<AnyCancellable> = []
    private var dragDistance: CGFloat = 0
    private var isDragging = false
    private var lastUpdateTime: TimeInterval?
    private var wasWalking = false
    private var handledEdge: CookieEdge?

    private let log = Logger(subsystem: "com.cookie.mac", category: "Scene")

    init(size: CGSize,
         store: CookieStore? = nil,
         behaviorEngine: CookieBehaviorEngine? = nil,
         audioManager: AudioManager? = nil,
         onPositionSettled: ((NSPoint) -> Void)? = nil) {
        self.store = store
        self.behaviorEngine = behaviorEngine
        self.audioManager = audioManager
        self.onPositionSettled = onPositionSettled
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

    // MARK: - Locomotion

    override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)
        defer { lastUpdateTime = currentTime }

        // Safety net: unless the user is holding Cookie right now, she can
        // never rest with her center outside the visible screen area —
        // covers missed mouse-ups and displays that changed mid-drag.
        if !isDragging, let window = view?.window {
            let safe = CookieScreenGeometry.safeOrigin(for: window.frame, in: NSScreen.screens)
            if safe != window.frame.origin {
                window.setFrameOrigin(safe)
                onPositionSettled?(safe)
            }
        }

        guard let engine = behaviorEngine, engine.isRunning else { return }
        let dt = min(0.1, currentTime - (lastUpdateTime ?? currentTime))

        let activity = engine.activity
        let direction: CGFloat
        switch activity {
        case .walkingLeft: direction = -1
        case .walkingRight: direction = 1
        default:
            if wasWalking {
                wasWalking = false
                handledEdge = nil
                if let window = view?.window {
                    onPositionSettled?(window.frame.origin)
                }
            }
            return
        }
        // A fresh walk clears the edge latch from the previous one.
        if wasWalking, handledEdge != nil, lastWalkingActivity != activity {
            handledEdge = nil
        }
        lastWalkingActivity = activity
        wasWalking = true

        guard let window = view?.window,
              let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        let speed = store?.profile.personality.walkSpeed ?? 26
        var frame = window.frame
        let margin: CGFloat = 8
        var newX = frame.origin.x + direction * speed * dt
        let minX = visible.minX + margin
        let maxX = visible.maxX - frame.width - margin
        if direction < 0, newX <= minX {
            newX = minX
            if handledEdge == nil {
                handledEdge = .left
                engine.handleEdgeReached(.left)
            }
        } else if direction > 0, newX >= maxX {
            newX = maxX
            if handledEdge == nil {
                handledEdge = .right
                engine.handleEdgeReached(.right)
            }
        }
        frame.origin.x = newX
        window.setFrameOrigin(frame.origin)
    }

    private var lastWalkingActivity: CookieActivity?

    // MARK: - Interaction

    override func mouseDown(with event: NSEvent) {
        dragDistance = 0
        isDragging = true
        behaviorEngine?.handleGrab()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = view?.window else { return }
        let origin = window.frame.origin
        window.setFrameOrigin(NSPoint(x: origin.x + event.deltaX, y: origin.y + event.deltaY))
        dragDistance += abs(event.deltaX) + abs(event.deltaY)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        defer { behaviorEngine?.resumeAfterRelease() }
        guard dragDistance < 4 else {
            // Dropped: keep her reachable and remember the spot.
            if let window = view?.window {
                let origin = CookieScreenGeometry.safeOrigin(for: window.frame, in: NSScreen.screens)
                window.setFrameOrigin(origin)
                onPositionSettled?(origin)
            }
            return
        }
        behaviorEngine?.registerPet()
        audioManager?.play(.pet)
    }
}
