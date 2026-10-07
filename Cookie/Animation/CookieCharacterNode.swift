import SpriteKit

/// The character as the scene sees it: a sprite node animated by
/// `SpriteAnimationController`, plus a vector accessory layer — the two
/// render layers stack on top of the artwork inside a container that
/// mirrors for direction.
final class CookieCharacterNode: SKNode, SpriteProviding {
    private(set) var state: CookieState = .idle

    private let container = SKNode()
    private let sprite = SKSpriteNode()
    private let shadow: SKShapeNode
    private let accessories = CookieAccessoryLayer()
    private let controller: SpriteAnimationController
    private var config: CookieAppearanceConfig

    init(config: CookieAppearanceConfig = CookieAppearanceConfig()) {
        self.config = config
        shadow = {
            let shadow = SKShapeNode(ellipseOf: CGSize(width: 96, height: 16))
            shadow.fillColor = SKColor.black.withAlphaComponent(0.09)
            shadow.strokeColor = .clear
            shadow.position = CGPoint(x: 0, y: -82)
            shadow.zPosition = -1
            return shadow
        }()
        controller = SpriteAnimationController(
            sprite: sprite,
            flipContainer: container,
            config: config,
            sources: [SpriteSheetSource(), ReferenceImageSource(), PlaceholderVectorSource()]
        )
        super.init()

        sprite.size = CookieSpriteRenderer.canvasSize
        container.addChild(sprite)
        container.addChild(accessories)
        addChild(shadow)
        addChild(container)
        accessories.rebuild(for: config)
        controller.setBase(.idle)
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - SpriteProviding

    func startIdling() {
        setState(.idle, facing: .right, reaction: .happy)
    }

    func setState(_ newState: CookieState, facing newFacing: CookieDirection, reaction newReaction: CookieReaction) {
        let facingChanged = newFacing != controller.facing
        guard newState != state || facingChanged else { return }
        state = newState

        // Whole-pose expression artwork takes precedence when the user
        // supplied it; otherwise the derived animation plays. Accessories
        // hide during poses whose silhouette differs from the base.
        if let art = CookieExpressionArt.forState(newState, reaction: newReaction),
           ExpressionArtSource.shared.texture(for: art, config: config) != nil {
            controller.show(art)
            controller.setFacing(newFacing)
            accessories.isHidden = CookieExpressionArt.poseFarFromBase.contains(art)
            return
        }
        accessories.isHidden = false

        switch newState {
        case .idle:
            controller.setBase(.idle)
        case .sitting:
            controller.setBase(.sit)
        case .curious:
            controller.setBase(.curious)
        case .sleeping:
            controller.setBase(.sleep)
        case .playing:
            controller.setBase(.playful)
        case .eating:
            controller.setBase(.eat)
        case .drinking:
            controller.setBase(.drink)
        case .beingDragged:
            controller.setBase(.pickedUp)
        case .walking, .followingCursor:
            controller.setBase(newFacing == .left ? .walkLeft : .walkRight)
        case .running:
            controller.setBase(newFacing == .left ? .runLeft : .runRight)
        case .stretching:
            controller.play(.stretch)
        case .yawning:
            controller.play(.yawn)
        case .grooming:
            controller.play(.groom)
        case .reacting:
            controller.play(newReaction == .annoyed ? .meow : .pet)
        case .special:
            controller.play(.jump)
        }
        controller.setFacing(newFacing)
    }

    func setIntensity(_ intensity: Double) {
        controller.animationIntensity = intensity
        controller.refresh()
    }

    func apply(config newConfig: CookieAppearanceConfig) {
        guard newConfig != config else { return }
        config = newConfig
        controller.updateConfig(newConfig)
        accessories.rebuild(for: newConfig)
        controller.refresh()
    }
}
