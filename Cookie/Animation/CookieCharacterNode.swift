import SpriteKit

/// The character as the scene sees it: a sprite node animated by
/// `SpriteAnimationController`, plus a vector accessory layer — the two
/// render layers stack on top of the artwork inside a container that
/// mirrors for direction.
final class CookieCharacterNode: SKNode, SpriteProviding {
    private(set) var state: CookieState = .idle
    private(set) var isPeeking: Bool = false

    private let container = SKNode()
    private let sprite = SKSpriteNode()
    private let shadow: SKShapeNode
    private let accessories = CookieAccessoryLayer()
    private let controller: SpriteAnimationController
    private var config: CookieAppearanceConfig

    private let boxBackNode: SKNode
    private let boxFrontNode: SKNode

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
        boxBackNode = Self.makeBoxBackNode()
        boxFrontNode = Self.makeBoxFrontNode()
        boxBackNode.isHidden = true
        boxFrontNode.isHidden = true

        controller = SpriteAnimationController(
            sprite: sprite,
            flipContainer: container,
            config: config,
            sources: [SpriteSheetSource(), ReferenceImageSource(), PlaceholderVectorSource()]
        )
        super.init()

        sprite.size = CookieSpriteRenderer.canvasSize
        container.addChild(boxBackNode)
        container.addChild(sprite)
        container.addChild(accessories)
        container.addChild(boxFrontNode)
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

    func setPeeking(_ peeking: Bool) {
        guard isPeeking != peeking else { return }
        isPeeking = peeking
        if state == .inBox {
            updateBoxAppearance()
        }
    }

    func setState(_ newState: CookieState, facing newFacing: CookieDirection, reaction newReaction: CookieReaction) {
        let facingChanged = newFacing != controller.facing
        guard newState != state || facingChanged else { return }
        state = newState

        if newState != .inBox {
            boxBackNode.isHidden = true
            boxFrontNode.isHidden = true
            shadow.isHidden = false
            sprite.position = .zero
        }

        // Whole-pose expression artwork takes precedence when the user
        // supplied it; otherwise the derived animation plays. Accessories
        // hide during poses whose silhouette differs from the base.
        if let art = CookieExpressionArt.forState(newState, reaction: newReaction),
           ExpressionArtSource.shared.texture(for: art, config: config) != nil {
            controller.show(art)
            controller.setFacing(newFacing)
            accessories.isHidden = CookieExpressionArt.poseFarFromBase.contains(art) || newState == .inBox
            return
        }
        accessories.isHidden = newState == .inBox

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
        case .investigating:
            controller.play(.investigate)
        case .tired:
            controller.setBase(.tired)
        case .inBox:
            updateBoxAppearance()
        }
        controller.setFacing(newFacing)
    }

    private func updateBoxAppearance() {
        boxBackNode.isHidden = false
        boxFrontNode.isHidden = false
        shadow.isHidden = true
        accessories.isHidden = true
        if isPeeking {
            sprite.position = CGPoint(x: 0, y: 2)
            controller.setBase(.boxPeek)
        } else {
            sprite.position = CGPoint(x: 0, y: -24)
            controller.setBase(.inBox)
        }
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

    // MARK: - Cardboard box graphics

    private static func makeBoxBackNode() -> SKNode {
        let node = SKNode()
        node.zPosition = -0.5
        let back = SKShapeNode(rectOf: CGSize(width: 114, height: 50), cornerRadius: 3)
        back.fillColor = SKColor(srgbRed: 0.60, green: 0.44, blue: 0.30, alpha: 1)
        back.strokeColor = SKColor(srgbRed: 0.46, green: 0.32, blue: 0.20, alpha: 1)
        back.lineWidth = 1.2
        back.position = CGPoint(x: 0, y: -34)
        node.addChild(back)

        let leftFlapPath = CGMutablePath()
        leftFlapPath.move(to: CGPoint(x: -57, y: -9))
        leftFlapPath.addLine(to: CGPoint(x: -70, y: 8))
        leftFlapPath.addLine(to: CGPoint(x: -15, y: 8))
        leftFlapPath.addLine(to: CGPoint(x: -15, y: -9))
        leftFlapPath.closeSubpath()
        let leftFlap = SKShapeNode(path: leftFlapPath)
        leftFlap.fillColor = SKColor(srgbRed: 0.66, green: 0.49, blue: 0.34, alpha: 1)
        leftFlap.strokeColor = SKColor(srgbRed: 0.46, green: 0.32, blue: 0.20, alpha: 1)
        leftFlap.lineWidth = 1.2
        node.addChild(leftFlap)

        let rightFlapPath = CGMutablePath()
        rightFlapPath.move(to: CGPoint(x: 15, y: -9))
        rightFlapPath.addLine(to: CGPoint(x: 15, y: 8))
        rightFlapPath.addLine(to: CGPoint(x: 70, y: 8))
        rightFlapPath.addLine(to: CGPoint(x: 57, y: -9))
        rightFlapPath.closeSubpath()
        let rightFlap = SKShapeNode(path: rightFlapPath)
        rightFlap.fillColor = SKColor(srgbRed: 0.66, green: 0.49, blue: 0.34, alpha: 1)
        rightFlap.strokeColor = SKColor(srgbRed: 0.46, green: 0.32, blue: 0.20, alpha: 1)
        rightFlap.lineWidth = 1.2
        node.addChild(rightFlap)

        return node
    }

    private static func makeBoxFrontNode() -> SKNode {
        let node = SKNode()
        node.zPosition = 2.0
        let front = SKShapeNode(rectOf: CGSize(width: 120, height: 52), cornerRadius: 4)
        front.fillColor = SKColor(srgbRed: 0.79, green: 0.62, blue: 0.44, alpha: 1)
        front.strokeColor = SKColor(srgbRed: 0.52, green: 0.38, blue: 0.25, alpha: 1)
        front.lineWidth = 1.5
        front.position = CGPoint(x: 0, y: -38)
        node.addChild(front)

        let tape = SKShapeNode(rectOf: CGSize(width: 24, height: 50), cornerRadius: 2)
        tape.fillColor = SKColor(srgbRed: 0.92, green: 0.88, blue: 0.76, alpha: 0.55)
        tape.strokeColor = .clear
        tape.position = CGPoint(x: 0, y: -38)
        node.addChild(tape)

        let leftFlapPath = CGMutablePath()
        leftFlapPath.move(to: CGPoint(x: -58, y: -12))
        leftFlapPath.addLine(to: CGPoint(x: -72, y: -26))
        leftFlapPath.addLine(to: CGPoint(x: -16, y: -26))
        leftFlapPath.addLine(to: CGPoint(x: -16, y: -12))
        leftFlapPath.closeSubpath()
        let leftFlap = SKShapeNode(path: leftFlapPath)
        leftFlap.fillColor = SKColor(srgbRed: 0.73, green: 0.56, blue: 0.39, alpha: 1)
        leftFlap.strokeColor = SKColor(srgbRed: 0.52, green: 0.38, blue: 0.25, alpha: 1)
        leftFlap.lineWidth = 1.2
        node.addChild(leftFlap)

        let rightFlapPath = CGMutablePath()
        rightFlapPath.move(to: CGPoint(x: 16, y: -12))
        rightFlapPath.addLine(to: CGPoint(x: 16, y: -26))
        rightFlapPath.addLine(to: CGPoint(x: 72, y: -26))
        rightFlapPath.addLine(to: CGPoint(x: 58, y: -12))
        rightFlapPath.closeSubpath()
        let rightFlap = SKShapeNode(path: rightFlapPath)
        rightFlap.fillColor = SKColor(srgbRed: 0.73, green: 0.56, blue: 0.39, alpha: 1)
        rightFlap.strokeColor = SKColor(srgbRed: 0.52, green: 0.38, blue: 0.25, alpha: 1)
        rightFlap.lineWidth = 1.2
        node.addChild(rightFlap)

        let stampPad = SKShapeNode(ellipseOf: CGSize(width: 8, height: 6))
        stampPad.fillColor = SKColor(srgbRed: 0.48, green: 0.34, blue: 0.22, alpha: 0.5)
        stampPad.strokeColor = .clear
        stampPad.position = CGPoint(x: 42, y: -48)
        node.addChild(stampPad)
        for dx in [-4.0, 0.0, 4.0] as [CGFloat] {
            let toe = SKShapeNode(circleOfRadius: 1.5)
            toe.fillColor = SKColor(srgbRed: 0.48, green: 0.34, blue: 0.22, alpha: 0.5)
            toe.strokeColor = .clear
            toe.position = CGPoint(x: 42 + dx, y: -42)
            node.addChild(toe)
        }

        return node
    }
}
