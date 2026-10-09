import SpriteKit
import Combine
import os

/// The scene behind the desktop companion (and the small preview views).
/// It renders whatever `SpriteProviding` character it is given, mirrors
/// appearance changes from the store, executes the behavior engine's
/// decisions every frame, and turns raw mouse input into interaction
/// events: clicks, double clicks, petting strokes, picking up and
/// dropping — each with the body zone that was touched.
final class CookieScene: SKScene {
    private let character: CookieCharacterNode
    private let store: CookieStore?
    private let behaviorEngine: CookieBehaviorEngine?
    private let audioManager: AudioManager?
    private let hitTester: CookieHitTester?
    /// Invoked whenever Cookie's position settles: after a drop, at the
    /// end of a walk, or when she stops at a screen edge.
    private let onPositionSettled: ((NSPoint) -> Void)?
    private var cancellables: Set<AnyCancellable> = []
    private var dragDistance: CGFloat = 0
    private var isDragging = false
    private var isCarrying = false
    private var grabZone: CookieZone?
    private var strokeAccumulator: CGFloat = 0
    /// Where the window and pointer were when the drag began — dragging
    /// maps pointer movement onto window movement 1:1, in the same
    /// coordinate system, so up is always up.
    private var dragAnchor: (windowOrigin: NSPoint, pointer: NSPoint)?
    private var lastPointer: NSPoint = .zero
    private var lastUpdateTime: TimeInterval?
    private var wasInLocomotion = false
    private var lastSoundKey: (state: CookieState, reaction: CookieReaction)?

    private let menuProvider: (() -> NSMenu?)?
    private let log = Logger(subsystem: "com.cookie.mac", category: "Scene")

    init(size: CGSize,
         store: CookieStore? = nil,
         behaviorEngine: CookieBehaviorEngine? = nil,
         audioManager: AudioManager? = nil,
         hitTester: CookieHitTester? = nil,
         menuProvider: (() -> NSMenu?)? = nil,
         onPositionSettled: ((NSPoint) -> Void)? = nil) {
        self.store = store
        self.behaviorEngine = behaviorEngine
        self.audioManager = audioManager
        self.hitTester = hitTester
        self.menuProvider = menuProvider
        self.onPositionSettled = onPositionSettled
        character = CookieCharacterNode(config: store?.profile.customization ?? CookieAppearanceConfig())
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
        centerCharacter()
        log.debug("Scene presented at \(Int(self.size.width), privacy: .public)×\(Int(self.size.height), privacy: .public)")
    }

    /// The scene uses .resizeFill, so its coordinate space matches the
    /// panel — when the Cookie size setting resizes the window, the
    /// character must re-center or she crops at the edges.
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        centerCharacter()
    }

    private func centerCharacter() {
        character.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    /// Used by preview views that render a specific configuration.
    func applyAppearance(_ config: CookieAppearanceConfig) {
        character.apply(config: config)
    }

    /// Applies Settings: Cookie size (panel + character + hit tester)
    /// and animation intensity.
    private func applySettings(_ settings: CookieSettings) {
        character.setIntensity(settings.animationIntensity)
        // The character's textures are designed for a 180pt canvas; the
        // panel base is 160pt — scale by the user's size setting AND that
        // ratio, or the cat overflows the panel at every size.
        let canvasRatio = CookieScreenGeometry.basePanelDimension / CookieSpriteRenderer.canvasSize.width
        character.setScale(CGFloat(settings.cookieSize * canvasRatio))
        centerCharacter()

        guard let view, let window = view.window else { return }
        let newSize = CookieScreenGeometry.basePanelSize(for: settings.cookieSize)
        guard abs(window.frame.width - newSize.width) > 0.5 else { return }
        var frame = window.frame
        let center = NSPoint(x: frame.midX, y: frame.midY)
        frame.size = newSize
        frame.origin = NSPoint(x: center.x - newSize.width / 2, y: center.y - newSize.height / 2)
        window.setFrame(frame, display: true)
        (view as? CompanionSKView)?.updateHitTester(canvasSize: newSize)
        centerCharacter()
    }

    private func bindObservers() {
        guard let store else { return }

        store.$profile
            .map(\.customization)
            .removeDuplicates()
            .sink { [weak self] config in
                self?.character.apply(config: config)
            }
            .store(in: &cancellables)

        store.$profile
            .map(\.settings)
            .removeDuplicates()
            .sink { [weak self] settings in
                self?.applySettings(settings)
            }
            .store(in: &cancellables)

        if let engine = behaviorEngine {
            engine.$noticeCount
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .dropFirst()
                .sink { [weak self] _ in
                    self?.audioManager?.play(.chirp)
                }
                .store(in: &cancellables)

            engine.$isPeeking
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] isPeeking in
                    self?.character.setPeeking(isPeeking)
                    if isPeeking {
                        self?.audioManager?.play(.mew)
                    }
                }
                .store(in: &cancellables)

            engine.$state.combineLatest(engine.$facing, engine.$reaction)
                .receive(on: DispatchQueue.main)
                .removeDuplicates { $0 == $1 }
                .sink { [weak self] state, facing, reaction in
                    self?.character.setState(state, facing: facing, reaction: reaction)
                    self?.playTransitionSound(state: state, reaction: reaction)
                    if state == .sleeping || state == .sitting || state == .idle || state == .inBox {
                        self?.store?.profile.lastRestingState = state
                    }
                }
                .store(in: &cancellables)

            engine.$activeEmote.combineLatest(engine.$emotePlaybackPhase)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] activeEmote, phase in
                    guard let self, let emote = activeEmote, phase == .starting else { return }
                    self.executeEmote(emote)
                }
                .store(in: &cancellables)
        }
    }

    /// Coordinates SpriteKit execution of an emote animation sequence.
    private func executeEmote(_ emote: Emote) {
        guard let engine = behaviorEngine else { return }
        engine.setEmotePlaybackPhase(.playing)
        if let sound = emote.soundIdentifier {
            audioManager?.play(sound)
        }
        if engine.wasSleepingBeforeEmote {
            character.playWakeThenEmote(emote) { [weak self] _ in
                self?.behaviorEngine?.completeEmote()
            }
        } else {
            character.playEmote(emote) { [weak self] _ in
                self?.behaviorEngine?.completeEmote()
            }
        }
    }

    /// Subtle feedback for state transitions — one small sound, never a
    /// barrage. Click reactions purr or meow; eating and playing have
    /// their own gentle effects.
    private func playTransitionSound(state: CookieState, reaction: CookieReaction) {
        guard let audioManager else { return }
        if let last = lastSoundKey, last.state == state, last.reaction == reaction { return }
        lastSoundKey = (state, reaction)
        switch (state, reaction) {
        case (.reacting, .happy): audioManager.play(.happy)
        case (.reacting, .annoyed): audioManager.play(.meow)
        case (.reacting, .surprised): audioManager.play(.surprise)
        case (.reacting, .meow): audioManager.play(.meow)
        case (.reacting, .shy): audioManager.play(.mew)
        case (.reacting, .dropped): audioManager.play(.drop)
        case (.reacting, .embarrassed): audioManager.play(.meow)
        case (.eating, _): audioManager.play(.eat)
        case (.drinking, _): audioManager.play(.eat)
        case (.playing, _): audioManager.play(.toy)
        case (.investigating, _): audioManager.play(.chirp)
        case (.inBox, _): audioManager.play(.purr)
        default: break
        }
    }

    // MARK: - Frame update

    private var lastScreenSafetyCheck: TimeInterval = 0

    override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)
        let dt = min(0.1, currentTime - (lastUpdateTime ?? currentTime))
        defer { lastUpdateTime = currentTime }

        // Sleeping CPU optimization: run at 15 FPS while sleeping to reduce CPU to ~0%
        if let engine = behaviorEngine {
            let targetFPS = engine.state == .sleeping ? 15 : 60
            if view?.preferredFramesPerSecond != targetFPS {
                view?.preferredFramesPerSecond = targetFPS
            }
        }

        // Throttled safety net: check screen validity periodically or when dropped,
        // avoiding wasteful NSScreen.screens IPC queries on every 16ms frame.
        if !isDragging, currentTime - lastScreenSafetyCheck >= 2.0, let window = view?.window {
            lastScreenSafetyCheck = currentTime
            let screens = NSScreen.screens
            let safe = CookieScreenGeometry.safeOrigin(for: window.frame, in: screens)
            if safe != window.frame.origin {
                window.setFrameOrigin(safe)
                onPositionSettled?(safe)
            }
        }

        guard let engine = behaviorEngine, engine.isRunning, dt > 0 else { return }

        let centerX = view?.window.map { $0.frame.midX } ?? 0
        engine.tick(dt: dt, currentX: centerX, cursorX: NSEvent.mouseLocation.x)
        applyLocomotion(from: engine, dt: CGFloat(dt))
    }

    private func applyLocomotion(from engine: CookieBehaviorEngine, dt: CGFloat) {
        let isLocomotion = engine.state.isLocomotion
        if isLocomotion, engine.locomotionVelocity != 0,
           let window = view?.window {
            let direction: CookieEdge = engine.locomotionVelocity > 0 ? .right : .left
            var frame = window.frame
            let visible = (window.screen ?? NSScreen.main)?.visibleFrame
            let margin: CGFloat = 8
            var newX = frame.origin.x + engine.locomotionVelocity * dt
            let minX = (visible?.minX ?? newX) + margin
            let maxX = (visible?.maxX ?? newX) - frame.width - margin
            if direction == .left, newX <= minX {
                newX = minX
                engine.handleEdgeReached(.left)
            } else if direction == .right, newX >= maxX {
                newX = maxX
                engine.handleEdgeReached(.right)
            }
            frame.origin.x = newX
            window.setFrameOrigin(frame.origin)
        } else if wasInLocomotion, let window = view?.window {
            onPositionSettled?(window.frame.origin)
        }
        wasInLocomotion = isLocomotion
    }

    // MARK: - Interaction

    private func zoneUnderMouse(for event: NSEvent) -> CookieZone? {
        guard let hitTester, let view else { return nil }
        // Route through the NSView explicitly (SKScene is also an SKNode,
        // whose convert overload would otherwise win).
        let local = view.convert(event.locationInWindow, from: nil)
        return hitTester.zone(at: local)
    }

    override func mouseDown(with event: NSEvent) {
        let pointer = NSEvent.mouseLocation
        dragDistance = 0
        strokeAccumulator = 0
        grabZone = zoneUnderMouse(for: event)
        dragAnchor = (windowOrigin: view?.window?.frame.origin ?? .zero, pointer: pointer)
        lastPointer = pointer
        isDragging = true
        isCarrying = false
        behaviorEngine?.handlePress()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchor = dragAnchor, let window = view?.window else { return }
        let pointer = NSEvent.mouseLocation
        dragDistance += hypot(pointer.x - lastPointer.x, pointer.y - lastPointer.y)

        // Commit to carrying only once the pointer actually moves.
        if dragDistance > 5, !isCarrying {
            isCarrying = true
            behaviorEngine?.handleGrab(zone: grabZone)
        }

        if isCarrying {
            // One-to-one with the pointer, in global y-up coordinates —
            // up is always up, and there is no accumulated drift.
            window.setFrameOrigin(NSPoint(
                x: anchor.windowOrigin.x + (pointer.x - anchor.pointer.x),
                y: anchor.windowOrigin.y + (pointer.y - anchor.pointer.y)
            ))
            // Stroking across her head or belly while she is carried
            // counts as petting: each sweep purrs and warms her up.
            if let grabZone, grabZone.isPettable {
                strokeAccumulator += hypot(pointer.x - lastPointer.x, pointer.y - lastPointer.y)
                if strokeAccumulator >= 55 {
                    strokeAccumulator = 0
                    behaviorEngine?.handlePetStroke(zone: grabZone)
                    audioManager?.play(.purr)
                }
            }
        }
        lastPointer = pointer
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        defer { dragAnchor = nil }
        if isCarrying {
            // Dropped: keep her reachable and land with a little boop.
            if let window = view?.window {
                let origin = CookieScreenGeometry.safeOrigin(for: window.frame, in: NSScreen.screens)
                window.setFrameOrigin(origin)
                onPositionSettled?(origin)
            }
            isCarrying = false
            behaviorEngine?.handleDrop()
        } else {
            behaviorEngine?.handleClick(zone: zoneUnderMouse(for: event))
            if let view, let menu = menuProvider?() {
                let localPoint = view.convert(event.locationInWindow, from: nil)
                menu.popUp(positioning: nil, at: localPoint, in: view)
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let view, let menu = menuProvider?() else { return }
        let localPoint = view.convert(event.locationInWindow, from: nil)
        menu.popUp(positioning: nil, at: localPoint, in: view)
    }
}
