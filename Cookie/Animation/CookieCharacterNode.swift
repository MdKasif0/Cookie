import SpriteKit

/// The placeholder Cookie: a soft, hand-drawn-style vector cat built from
/// SpriteKit shape nodes. It is deliberately simple stand-in artwork —
/// everything downstream (scene, behaviors, persistence) only talks to the
/// `SpriteProviding` protocol, so the final sprite sheet drops in later
/// without touching this file's callers.
final class CookieCharacterNode: SKNode, SpriteProviding {
    private(set) var activity: CookieActivity = .idle
    private var palette: CharacterPalette

    private var tailNode = SKNode()
    private var eyesNode = SKNode()
    private var happyEyesNode = SKNode()

    init(palette: CharacterPalette = .standard(for: .classicCream)) {
        self.palette = palette
        super.init()
        rebuild()
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - SpriteProviding

    func startIdling() {
        activity = .idle
        happyEyesNode.isHidden = true
        eyesNode.isHidden = false
        removeAllActions()
        eyesNode.removeAction(forKey: "glance")
        run(CookieAnimationFactory.breathing())
        tailNode.run(CookieAnimationFactory.tailSway())
        eyesNode.run(CookieAnimationFactory.blinking())
    }

    func setActivity(_ newActivity: CookieActivity) {
        guard newActivity != activity else { return }
        switch newActivity {
        case .idle:
            startIdling()
        case .watching:
            activity = .watching
            happyEyesNode.isHidden = true
            eyesNode.isHidden = false
            eyesNode.removeAction(forKey: "glance")
            eyesNode.run(CookieAnimationFactory.glance(), withKey: "glance")
        case .delighted:
            playPetReaction()
        }
    }

    func playPetReaction() {
        activity = .delighted
        eyesNode.isHidden = true
        happyEyesNode.isHidden = false
        eyesNode.removeAction(forKey: "glance")
        removeAllActions()
        run(CookieAnimationFactory.hop()) { [weak self] in
            self?.startIdling()
        }
    }

    func apply(palette newPalette: CharacterPalette) {
        guard newPalette != palette else { return }
        palette = newPalette
        rebuild()
    }

    // MARK: - Construction

    private func rebuild() {
        removeAllActions()
        removeAllChildren()

        let shadow = ellipse(CGSize(width: 74, height: 12), fill: SKColor.black.withAlphaComponent(0.08))
        shadow.position = CGPoint(x: 0, y: -72)
        shadow.zPosition = -3
        addChild(shadow)

        let tail = makeTail()
        tail.zPosition = -2
        tailNode = tail
        addChild(tail)

        let body = outlinedEllipse(CGSize(width: 88, height: 72), fill: palette.fur, outline: palette.outline)
        body.position = CGPoint(x: 0, y: -26)
        addChild(body)

        let sides: [CGFloat] = [-1, 1]
        for side in sides {
            let paw = outlinedEllipse(CGSize(width: 20, height: 13), fill: palette.fur, outline: palette.outline, width: 3.5)
            paw.position = CGPoint(x: side * 16, y: -58)
            paw.zPosition = 1
            addChild(paw)
        }

        addChild(makeHead())

        // Resume the loop the character was in before the rebuild
        let previous = activity
        activity = .idle
        if previous == .watching {
            setActivity(.watching)
        } else {
            startIdling()
        }
    }

    private func makeHead() -> SKNode {
        let head = SKNode()
        head.position = CGPoint(x: 0, y: 30)
        head.zPosition = 2

        let sides: [CGFloat] = [-1, 1]
        for side in sides {
            let ear = triangle(
                [CGPoint(x: side * 30, y: 22), CGPoint(x: side * 20, y: 52), CGPoint(x: side * 6, y: 30)],
                fill: palette.fur,
                outline: palette.outline
            )
            head.addChild(ear)
            let innerEar = triangle(
                [CGPoint(x: side * 24, y: 28), CGPoint(x: side * 19, y: 44), CGPoint(x: side * 11, y: 31)],
                fill: palette.innerEar,
                outline: nil
            )
            innerEar.alpha = 0.9
            head.addChild(innerEar)
        }

        let skull = outlinedEllipse(CGSize(width: 82, height: 72), fill: palette.fur, outline: palette.outline)
        skull.zPosition = 1
        head.addChild(skull)

        let stripes = lines([
            (CGPoint(x: 12, y: 20), CGPoint(x: 12, y: 32)),
            (CGPoint(x: 19, y: 18), CGPoint(x: 19, y: 29)),
            (CGPoint(x: 26, y: 15), CGPoint(x: 26, y: 24))
        ], stroke: palette.stripe, lineWidth: 5)
        stripes.alpha = 0.85
        stripes.zPosition = 2
        head.addChild(stripes)

        eyesNode = SKNode()
        eyesNode.zPosition = 2
        for side in sides {
            let eye = ellipse(CGSize(width: 9, height: 12), fill: palette.eye)
            eye.position = CGPoint(x: side * 15, y: 2)
            eyesNode.addChild(eye)
        }
        head.addChild(eyesNode)

        happyEyesNode = SKNode()
        happyEyesNode.zPosition = 2
        happyEyesNode.isHidden = true
        for side in sides {
            let happyEye = arc(center: CGPoint(x: side * 15, y: 2), radius: 8, startAngle: 0, endAngle: 180, stroke: palette.eye, lineWidth: 3)
            happyEyesNode.addChild(happyEye)
        }
        head.addChild(happyEyesNode)

        for side in sides {
            let cheek = circle(radius: 8, fill: palette.blush)
            cheek.alpha = 0.55
            cheek.position = CGPoint(x: side * 27, y: -8)
            cheek.zPosition = 2
            head.addChild(cheek)
        }

        let mouthLeft = arc(center: CGPoint(x: -3.5, y: -9), radius: 4.5, startAngle: 180, endAngle: 360, stroke: palette.eye, lineWidth: 2.5)
        let mouthRight = arc(center: CGPoint(x: 3.5, y: -9), radius: 4.5, startAngle: 180, endAngle: 360, stroke: palette.eye, lineWidth: 2.5)
        mouthLeft.zPosition = 2
        mouthRight.zPosition = 2
        head.addChild(mouthLeft)
        head.addChild(mouthRight)

        for side in sides {
            let whiskers = lines([
                (CGPoint(x: side * 36, y: -2), CGPoint(x: side * 54, y: 2)),
                (CGPoint(x: side * 36, y: -9), CGPoint(x: side * 54, y: -13))
            ], stroke: palette.eye, lineWidth: 2)
            whiskers.alpha = 0.45
            whiskers.zPosition = 2
            head.addChild(whiskers)
        }

        return head
    }

    private func makeTail() -> SKNode {
        let tail = SKNode()
        tail.position = CGPoint(x: 26, y: -20)

        let path = NSBezierPath()
        path.move(to: .zero)
        path.curve(to: CGPoint(x: 36, y: -2), controlPoint1: CGPoint(x: 14, y: 12), controlPoint2: CGPoint(x: 30, y: 10))
        path.curve(to: CGPoint(x: 46, y: -30), controlPoint1: CGPoint(x: 42, y: -12), controlPoint2: CGPoint(x: 50, y: -20))

        let outline = SKShapeNode(path: path.cgPath)
        outline.strokeColor = palette.outline
        outline.fillColor = .clear
        outline.lineWidth = 15
        outline.lineCap = .round
        tail.addChild(outline)

        let fur = SKShapeNode(path: path.cgPath)
        fur.strokeColor = palette.fur
        fur.fillColor = .clear
        fur.lineWidth = 10
        fur.lineCap = .round
        fur.zPosition = 1
        tail.addChild(fur)

        let tip = outlinedEllipse(CGSize(width: 13, height: 13), fill: palette.furShade, outline: palette.outline, width: 3)
        tip.position = CGPoint(x: 46, y: -30)
        tip.zPosition = 2
        tail.addChild(tip)

        return tail
    }

    // MARK: - Shape helpers

    private func ellipse(_ size: CGSize, fill: SKColor) -> SKShapeNode {
        let node = SKShapeNode(ellipseOf: size)
        node.fillColor = fill
        node.strokeColor = .clear
        return node
    }

    private func circle(radius: CGFloat, fill: SKColor) -> SKShapeNode {
        ellipse(CGSize(width: radius * 2, height: radius * 2), fill: fill)
    }

    private func outlinedEllipse(_ size: CGSize, fill: SKColor, outline: SKColor, width: CGFloat = 4) -> SKShapeNode {
        let node = SKShapeNode(ellipseOf: size)
        node.fillColor = fill
        node.strokeColor = outline
        node.lineWidth = width
        return node
    }

    private func triangle(_ points: [CGPoint], fill: SKColor, outline: SKColor?, width: CGFloat = 5) -> SKShapeNode {
        let path = NSBezierPath()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.line(to: point)
        }
        path.close()
        let node = SKShapeNode(path: path.cgPath)
        node.fillColor = fill
        node.strokeColor = outline ?? .clear
        node.lineWidth = width
        node.lineJoin = .round
        return node
    }

    private func arc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, stroke: SKColor, lineWidth: CGFloat) -> SKShapeNode {
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        let node = SKShapeNode(path: path.cgPath)
        node.strokeColor = stroke
        node.fillColor = .clear
        node.lineWidth = lineWidth
        node.lineCap = .round
        return node
    }

    private func lines(_ segments: [(CGPoint, CGPoint)], stroke: SKColor, lineWidth: CGFloat) -> SKShapeNode {
        let path = NSBezierPath()
        for (start, end) in segments {
            path.move(to: start)
            path.line(to: end)
        }
        let node = SKShapeNode(path: path.cgPath)
        node.strokeColor = stroke
        node.fillColor = .clear
        node.lineWidth = lineWidth
        node.lineCap = .round
        return node
    }
}
