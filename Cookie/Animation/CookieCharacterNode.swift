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
    private var activeEmoteEffect: SKNode?

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
        if newState != .emoting {
            clearEmoteEffects()
        }

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
        case .emoting:
            break
        }
        controller.setFacing(newFacing)
    }

    /// Triggers a dedicated emote animation on Cookie with natural SpriteKit completion.
    func playEmote(_ emote: Emote, completion: @escaping (Bool) -> Void) {
        state = .emoting
        displayEmoteEffects(for: emote)
        if let art = CookieExpressionArt.forEmote(emote.id),
           let texture = ExpressionArtSource.shared.texture(for: art, config: config) {
            playExpressionStickerEmote(art: art, emote: emote, texture: texture, completion: completion)
            return
        }
        controller.play(emote.animationIdentifier) { [weak self] finished in
            self?.clearEmoteEffects()
            completion(finished)
        }
    }

    /// Plays dedicated whole-pose artwork emotes with custom expressive SpriteKit actions and natural idle return.
    private func playExpressionStickerEmote(art: CookieExpressionArt, emote: Emote, texture: SKTexture, completion: @escaping (Bool) -> Void) {
        sprite.removeAction(forKey: CookieAnimationId.actionKey)
        sprite.removeAction(forKey: "cookie.bob")
        sprite.texture = texture
        sprite.position = .zero
        accessories.isHidden = CookieExpressionArt.poseFarFromBase.contains(art)

        let duration = emote.duration

        if MotionSettings.reduceMotion {
            sprite.alpha = 0.8
            sprite.run(.sequence([
                .fadeAlpha(to: 1.0, duration: 0.15),
                .wait(forDuration: duration * 0.8),
                .run { [weak self] in
                    self?.clearEmoteEffects()
                    self?.accessories.isHidden = false
                    self?.startIdling()
                    completion(true)
                }
            ]), withKey: CookieAnimationId.actionKey)
            return
        }

        let animationSequence: SKAction

        switch emote.id {
        case .wave:
            // Cheerful spring and adorable waving rocking
            let prep = SKAction.group([
                .scaleX(to: 1.04, duration: 0.12),
                .scaleY(to: 0.96, duration: 0.12)
            ])
            let springUp = SKAction.group([
                .scaleX(to: 0.98, duration: 0.18),
                .scaleY(to: 1.04, duration: 0.18),
                .moveBy(x: 0, y: 3.5, duration: 0.18)
            ])
            let wave1 = SKAction.rotate(toAngle: 0.08, duration: 0.18)
            let wave2 = SKAction.rotate(toAngle: -0.07, duration: 0.20)
            let wave3 = SKAction.rotate(toAngle: 0.09, duration: 0.20)
            let wave4 = SKAction.rotate(toAngle: -0.06, duration: 0.20)
            let waveReset = SKAction.rotate(toAngle: 0.0, duration: 0.18)
            let settle = SKAction.group([
                .scaleX(to: 1.0, duration: 0.22),
                .scaleY(to: 1.0, duration: 0.22),
                .moveTo(y: 0, duration: 0.22)
            ])
            let hold = SKAction.wait(forDuration: 0.35)
            animationSequence = .sequence([prep, springUp, wave1, wave2, wave3, wave4, waveReset, settle, hold])

        case .love:
            // Affectionate blushing lean, sweet snuggle tilt, and gentle heartbeat purr pulse
            let snuggleLean = SKAction.group([
                .scaleX(to: 1.03, duration: 0.22),
                .scaleY(to: 0.97, duration: 0.22),
                .rotate(toAngle: 0.06, duration: 0.22),
                .moveBy(x: 2, y: 1, duration: 0.22)
            ])
            let pulse1 = SKAction.sequence([
                .scale(to: 1.03, duration: 0.25),
                .scale(to: 0.99, duration: 0.25)
            ])
            let pulse2 = SKAction.sequence([
                .scale(to: 1.025, duration: 0.25),
                .scale(to: 0.995, duration: 0.25)
            ])
            let unLean = SKAction.group([
                .scaleX(to: 1.0, duration: 0.30),
                .scaleY(to: 1.0, duration: 0.30),
                .rotate(toAngle: 0.0, duration: 0.30),
                .move(to: .zero, duration: 0.30)
            ])
            let hold = SKAction.wait(forDuration: 0.20)
            animationSequence = .sequence([snuggleLean, pulse1, pulse2, unLean, hold])

        case .sleepy:
            // Settle down peacefully into sleep curl, gentle deep breathing cycles
            let curlDown = SKAction.group([
                .scaleY(to: 0.96, duration: 0.35),
                .moveTo(y: -1, duration: 0.35)
            ])
            let breathIn1 = SKAction.scaleY(to: 0.985, duration: 0.75)
            let breathOut1 = SKAction.scaleY(to: 0.945, duration: 0.75)
            let breathIn2 = SKAction.scaleY(to: 0.985, duration: 0.75)
            let breathOut2 = SKAction.scaleY(to: 0.945, duration: 0.75)
            let wakeUp = SKAction.group([
                .scaleX(to: 1.0, duration: 0.40),
                .scaleY(to: 1.0, duration: 0.40),
                .moveTo(y: 0, duration: 0.40)
            ])
            animationSequence = .sequence([curlDown, breathIn1, breathOut1, breathIn2, breathOut2, wakeUp])

        case .happy:
            // Joyful excited leaps, happy landing squash, and sweet wiggle
            let crouch = SKAction.group([
                .scaleX(to: 1.04, duration: 0.12),
                .scaleY(to: 0.95, duration: 0.12)
            ])
            let hop1 = SKAction.group([
                .scaleX(to: 0.97, duration: 0.16),
                .scaleY(to: 1.06, duration: 0.16),
                .moveBy(x: 0, y: 6.5, duration: 0.16)
            ])
            let land1 = SKAction.group([
                .scaleX(to: 1.03, duration: 0.14),
                .scaleY(to: 0.96, duration: 0.14),
                .moveTo(y: 0, duration: 0.14)
            ])
            let hop2 = SKAction.group([
                .scaleX(to: 0.98, duration: 0.15),
                .scaleY(to: 1.04, duration: 0.15),
                .moveBy(x: 0, y: 4.5, duration: 0.15)
            ])
            let land2 = SKAction.group([
                .scaleX(to: 1.0, duration: 0.16),
                .scaleY(to: 1.0, duration: 0.16),
                .moveTo(y: 0, duration: 0.16)
            ])
            let wiggle1 = SKAction.rotate(toAngle: 0.05, duration: 0.14)
            let wiggle2 = SKAction.rotate(toAngle: -0.05, duration: 0.14)
            let wiggleReset = SKAction.rotate(toAngle: 0.0, duration: 0.12)
            let hold = SKAction.wait(forDuration: 0.25)
            animationSequence = .sequence([crouch, hop1, land1, hop2, land2, wiggle1, wiggle2, wiggleReset, hold])

        case .playful:
            // Mischievous pounce crouch, wiggle, playful leap and waggle
            let pouncePrep = SKAction.group([
                .scaleX(to: 1.05, duration: 0.14),
                .scaleY(to: 0.94, duration: 0.14),
                .moveBy(x: -2, y: -1, duration: 0.14)
            ])
            let buttWiggle = SKAction.sequence([
                .rotate(toAngle: -0.06, duration: 0.10),
                .rotate(toAngle: 0.06, duration: 0.10),
                .rotate(toAngle: -0.05, duration: 0.10),
                .rotate(toAngle: 0.0, duration: 0.08)
            ])
            let pounce = SKAction.group([
                .scaleX(to: 0.97, duration: 0.18),
                .scaleY(to: 1.06, duration: 0.18),
                .moveBy(x: 4, y: 5.5, duration: 0.18)
            ])
            let land = SKAction.group([
                .scaleX(to: 1.02, duration: 0.20),
                .scaleY(to: 0.97, duration: 0.20),
                .move(to: .zero, duration: 0.20)
            ])
            let recover = SKAction.group([
                .scaleX(to: 1.0, duration: 0.22),
                .scaleY(to: 1.0, duration: 0.22)
            ])
            let hold = SKAction.wait(forDuration: 0.35)
            animationSequence = .sequence([pouncePrep, buttWiggle, pounce, land, recover, hold])
        }

        let fullSequence = SKAction.sequence([
            animationSequence,
            .run { [weak self] in
                self?.clearEmoteEffects()
                self?.accessories.isHidden = false
                self?.startIdling()
                completion(true)
            }
        ])
        sprite.run(fullSequence, withKey: CookieAnimationId.actionKey)
    }

    /// Awakens Cookie naturally before seamlessly playing the requested emote.
    func playWakeThenEmote(_ emote: Emote, onEmoteStart: (() -> Void)? = nil, completion: @escaping (Bool) -> Void) {
        state = .emoting
        clearEmoteEffects()
        controller.play(.wake) { [weak self] _ in
            guard let self else {
                completion(false)
                return
            }
            onEmoteStart?()
            self.playEmote(emote, completion: completion)
        }
    }

    /// Immediately cancels and cleans up any active secondary emote effect nodes.
    func clearEmoteEffects() {
        activeEmoteEffect?.removeAllActions()
        activeEmoteEffect?.removeFromParent()
        activeEmoteEffect = nil
    }

    /// Spawns subtle, tasteful secondary effects for emotes that benefit from them.
    private func displayEmoteEffects(for emote: Emote) {
        clearEmoteEffects()
        switch emote.id {
        case .wave:
            let greetingNode = SKNode()
            greetingNode.position = CGPoint(x: 28, y: 38)
            greetingNode.zPosition = 3.0
            greetingNode.alpha = 0

            // Warm cream speech bubble with soft orange outline
            let bgWidth: CGFloat = 48
            let bgHeight: CGFloat = 20
            let bgRect = CGRect(x: -bgWidth / 2, y: -bgHeight / 2, width: bgWidth, height: bgHeight)
            let bubble = SKShapeNode(rect: bgRect, cornerRadius: 10)
            bubble.fillColor = SKColor(srgbRed: 0.99, green: 0.96, blue: 0.90, alpha: 0.95)
            bubble.strokeColor = SKColor(srgbRed: 0.91, green: 0.61, blue: 0.41, alpha: 0.85)
            bubble.lineWidth = 1.2
            greetingNode.addChild(bubble)

            // "Hii! ✨" label
            let label = SKLabelNode(text: "Hii! ✨")
            label.fontName = "Helvetica-Bold"
            label.fontSize = 10.5
            label.fontColor = SKColor(srgbRed: 0.44, green: 0.31, blue: 0.22, alpha: 1.0)
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            greetingNode.addChild(label)

            // Sparkling burst star near waving paw
            let spark = SKLabelNode(text: "✦")
            spark.fontName = "Helvetica-Bold"
            spark.fontSize = 13
            spark.fontColor = SKColor(srgbRed: 0.96, green: 0.72, blue: 0.35, alpha: 0.95)
            spark.position = CGPoint(x: -28, y: -2)
            greetingNode.addChild(spark)

            container.addChild(greetingNode)
            activeEmoteEffect = greetingNode

            if MotionSettings.reduceMotion {
                greetingNode.run(.sequence([
                    .fadeIn(withDuration: 0.25),
                    .wait(forDuration: 1.3),
                    .fadeOut(withDuration: 0.35),
                    .run { [weak self] in self?.clearEmoteEffects() }
                ]))
            } else {
                let popIn = SKAction.group([
                    .fadeIn(withDuration: 0.20),
                    .scale(to: 1.0, duration: 0.20),
                    .moveBy(x: 2, y: 6, duration: 0.20)
                ])
                let floatSway = SKAction.sequence([
                    .moveBy(x: 0, y: 2.5, duration: 0.35),
                    .moveBy(x: 0, y: -2.5, duration: 0.35),
                    .moveBy(x: 0, y: 1.5, duration: 0.3)
                ])
                let fadeOut = SKAction.group([
                    .fadeOut(withDuration: 0.35),
                    .scale(to: 0.8, duration: 0.35),
                    .moveBy(x: 0, y: 4, duration: 0.35)
                ])
                greetingNode.setScale(0.5)
                greetingNode.run(.sequence([
                    popIn,
                    floatSway,
                    fadeOut,
                    .run { [weak self] in self?.clearEmoteEffects() }
                ]))
            }
        case .love:
            let heart = SKShapeNode(path: Self.makeHeartPath(size: 14))
            heart.fillColor = SKColor(srgbRed: 0.94, green: 0.62, blue: 0.50, alpha: 0.95)
            heart.strokeColor = SKColor(srgbRed: 0.84, green: 0.48, blue: 0.38, alpha: 0.90)
            heart.lineWidth = 1.0
            heart.position = CGPoint(x: 24, y: 28)
            heart.zPosition = 3.0
            heart.alpha = 0
            container.addChild(heart)
            activeEmoteEffect = heart

            if MotionSettings.reduceMotion {
                heart.run(.sequence([
                    .fadeIn(withDuration: 0.3),
                    .wait(forDuration: 1.0),
                    .fadeOut(withDuration: 0.4),
                    .run { [weak self] in self?.clearEmoteEffects() }
                ]))
            } else {
                let appear = SKAction.group([
                    .fadeIn(withDuration: 0.25),
                    .scale(to: 1.0, duration: 0.25)
                ])
                let drift = SKAction.group([
                    .moveBy(x: 4, y: 16, duration: 1.2),
                    .sequence([
                        .wait(forDuration: 0.8),
                        .fadeOut(withDuration: 0.4)
                    ])
                ])
                heart.setScale(0.5)
                heart.run(.sequence([
                    appear,
                    drift,
                    .run { [weak self] in self?.clearEmoteEffects() }
                ]))
            }

        case .sleepy:
            let zLabel = SKLabelNode(text: "z")
            zLabel.fontName = "Helvetica-Bold"
            zLabel.fontSize = 13
            zLabel.fontColor = SKColor(srgbRed: 0.52, green: 0.45, blue: 0.38, alpha: 0.85)
            zLabel.position = CGPoint(x: 20, y: 38)
            zLabel.zPosition = 3.0
            zLabel.alpha = 0
            container.addChild(zLabel)
            activeEmoteEffect = zLabel

            if MotionSettings.reduceMotion {
                zLabel.run(.sequence([
                    .wait(forDuration: 1.4),
                    .fadeIn(withDuration: 0.3),
                    .wait(forDuration: 1.2),
                    .fadeOut(withDuration: 0.4),
                    .run { [weak self] in self?.clearEmoteEffects() }
                ]))
            } else {
                let delay = SKAction.wait(forDuration: 1.4)
                let appear = SKAction.group([
                    .fadeIn(withDuration: 0.3),
                    .scale(to: 1.0, duration: 0.3)
                ])
                let drift = SKAction.group([
                    .moveBy(x: 3, y: 12, duration: 1.5),
                    .sequence([
                        .wait(forDuration: 1.0),
                        .fadeOut(withDuration: 0.5)
                    ])
                ])
                zLabel.setScale(0.6)
                zLabel.run(.sequence([
                    delay,
                    appear,
                    drift,
                    .run { [weak self] in self?.clearEmoteEffects() }
                ]))
            }

        case .happy:
            let sparksNode = SKNode()
            sparksNode.position = CGPoint(x: 0, y: 32)
            sparksNode.zPosition = 3.0
            sparksNode.alpha = 0

            let leftSpark = SKLabelNode(text: "✨")
            leftSpark.fontSize = 12
            leftSpark.position = CGPoint(x: -24, y: 4)
            sparksNode.addChild(leftSpark)

            let rightSpark = SKLabelNode(text: "✨")
            rightSpark.fontSize = 12
            rightSpark.position = CGPoint(x: 24, y: 8)
            sparksNode.addChild(rightSpark)

            container.addChild(sparksNode)
            activeEmoteEffect = sparksNode

            if MotionSettings.reduceMotion {
                sparksNode.run(.sequence([
                    .fadeIn(withDuration: 0.25),
                    .wait(forDuration: 1.0),
                    .fadeOut(withDuration: 0.35),
                    .run { [weak self] in self?.clearEmoteEffects() }
                ]))
            } else {
                let appear = SKAction.group([
                    .fadeIn(withDuration: 0.20),
                    .scale(to: 1.1, duration: 0.20)
                ])
                let drift = SKAction.group([
                    .moveBy(x: 0, y: 12, duration: 1.1),
                    .sequence([
                        .wait(forDuration: 0.7),
                        .fadeOut(withDuration: 0.4)
                    ])
                ])
                sparksNode.setScale(0.5)
                sparksNode.run(.sequence([
                    appear,
                    drift,
                    .run { [weak self] in self?.clearEmoteEffects() }
                ]))
            }

        case .playful:
            let toyNode = SKNode()
            toyNode.position = CGPoint(x: 24, y: 26)
            toyNode.zPosition = 3.0
            toyNode.alpha = 0

            let yarn = SKLabelNode(text: "🧶")
            yarn.fontSize = 13
            yarn.position = CGPoint(x: 0, y: 0)
            toyNode.addChild(yarn)

            let spark = SKLabelNode(text: "✦")
            spark.fontSize = 11
            spark.fontColor = SKColor(srgbRed: 0.95, green: 0.65, blue: 0.40, alpha: 0.95)
            spark.position = CGPoint(x: -14, y: 12)
            toyNode.addChild(spark)

            container.addChild(toyNode)
            activeEmoteEffect = toyNode

            if MotionSettings.reduceMotion {
                toyNode.run(.sequence([
                    .fadeIn(withDuration: 0.25),
                    .wait(forDuration: 1.2),
                    .fadeOut(withDuration: 0.35),
                    .run { [weak self] in self?.clearEmoteEffects() }
                ]))
            } else {
                let pop = SKAction.group([
                    .fadeIn(withDuration: 0.20),
                    .scale(to: 1.1, duration: 0.20),
                    .moveBy(x: 2, y: 6, duration: 0.20)
                ])
                let bounce = SKAction.sequence([
                    .moveBy(x: 0, y: -4, duration: 0.25),
                    .moveBy(x: 0, y: 2, duration: 0.25),
                    .wait(forDuration: 0.6),
                    .fadeOut(withDuration: 0.35)
                ])
                toyNode.setScale(0.5)
                toyNode.run(.sequence([
                    pop,
                    bounce,
                    .run { [weak self] in self?.clearEmoteEffects() }
                ]))
            }
        }
    }

    private static func makeHeartPath(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let s = size / 2.0
        path.move(to: CGPoint(x: 0, y: -s * 0.8))
        path.addCurve(to: CGPoint(x: -s, y: s * 0.2),
                      control1: CGPoint(x: -s * 0.2, y: -s * 0.5),
                      control2: CGPoint(x: -s, y: -s * 0.2))
        path.addArc(tangent1End: CGPoint(x: -s, y: s * 0.9),
                    tangent2End: CGPoint(x: 0, y: s * 0.9),
                    radius: s * 0.45)
        path.addArc(tangent1End: CGPoint(x: s, y: s * 0.9),
                    tangent2End: CGPoint(x: s, y: s * 0.2),
                    radius: s * 0.45)
        path.addCurve(to: CGPoint(x: 0, y: -s * 0.8),
                      control1: CGPoint(x: s, y: -s * 0.2),
                      control2: CGPoint(x: 0.2, y: -s * 0.5))
        path.closeSubpath()
        return path
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
