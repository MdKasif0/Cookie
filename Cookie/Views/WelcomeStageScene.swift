import SpriteKit

/// The little stage at the top of the welcome window, where Cookie first appears.
@MainActor
final class WelcomeStageScene: SKScene {
    private static let stageSize = CGSize(width: 480, height: 232)
    private static let characterScale: CGFloat = 1.08
    private static let groundY: CGFloat = 104

    private let character: CookieCharacterNode
    private var hasEntered = false
    private var isReady = false
    private var settleWork: DispatchWorkItem?

    init(config: CookieAppearanceConfig) {
        character = CookieCharacterNode(config: config)
        super.init(size: Self.stageSize)
        backgroundColor = .clear
        scaleMode = .aspectFill
        character.setScale(Self.characterScale)
        character.position = CGPoint(x: -120, y: Self.groundY)
        addChild(character)
    }

    required init?(coder: NSCoder) { nil }

    private var restingX: CGFloat { size.width / 2 - 34 }

    func walkIn(completion: @escaping () -> Void) {
        guard !hasEntered else { return }
        hasEntered = true

        if MotionSettings.reduceMotion {
            character.position.x = restingX
            character.startIdling()
            isReady = true
            completion()
            return
        }

        character.setState(.walking, facing: .right, reaction: .happy)
        let walk = SKAction.moveTo(x: restingX, duration: 2.1)
        walk.timingMode = .easeOut
        character.run(walk) { [weak self] in
            guard let self else { return }
            self.isReady = true
            self.character.setState(.reacting, facing: .right, reaction: .happy)
            completion()
            self.settle(after: 1.3)
        }
    }

    /// A quick glance and hop for each burst of typing.
    func reactToTyping() {
        guard isReady else { return }
        character.setState(.curious, facing: .right, reaction: .happy)
        if !MotionSettings.reduceMotion, character.action(forKey: "typingHop") == nil {
            let up = SKAction.moveBy(x: 0, y: 7, duration: 0.09)
            up.timingMode = .easeOut
            let down = SKAction.moveTo(y: Self.groundY, duration: 0.11)
            down.timingMode = .easeIn
            character.run(.sequence([up, down]), withKey: "typingHop")
        }
        settle(after: 1.1)
    }

    /// Cookie tries on a personality.
    func actOut(_ personality: CookiePersonality) {
        guard isReady else { return }
        let hold: TimeInterval
        switch personality {
        case .sleepy:
            character.setState(.sleeping, facing: .right, reaction: .happy)
            hold = 2.6
        case .playful:
            character.setState(.playing, facing: .right, reaction: .happy)
            hold = 2.0
        case .affectionate:
            character.setState(.reacting, facing: .right, reaction: .shy)
            hold = 1.8
        case .energetic:
            zoom()
            hold = 1.5
        case .curious:
            character.setState(.investigating, facing: .right, reaction: .happy)
            hold = 1.8
        case .grumpy:
            character.setState(.reacting, facing: .right, reaction: .annoyed)
            hold = 1.8
        }
        settle(after: hold)
    }

    private func zoom() {
        guard !MotionSettings.reduceMotion else {
            character.setState(.reacting, facing: .right, reaction: .happy)
            return
        }
        character.removeAction(forKey: "zoom")
        character.setState(.running, facing: .right, reaction: .happy)
        let out = SKAction.moveTo(x: restingX + 92, duration: 0.45)
        out.timingMode = .easeInEaseOut
        let turn = SKAction.run { [weak self] in
            self?.character.setState(.running, facing: .left, reaction: .happy)
        }
        let back = SKAction.moveTo(x: restingX, duration: 0.55)
        back.timingMode = .easeInEaseOut
        character.run(.sequence([out, turn, back]), withKey: "zoom")
    }

    private func settle(after delay: TimeInterval) {
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.character.setState(.idle, facing: .right, reaction: .happy)
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
