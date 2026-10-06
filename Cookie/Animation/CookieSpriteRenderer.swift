import SpriteKit

/// Draws a single `CookiePose` as a SpriteKit node tree. Used by the
/// placeholder texture source to bake poses into cached textures; the
/// character itself is rendered from those textures, never from live
/// shape nodes.
enum CookieSpriteRenderer {
    /// The pose canvas: every frame is rendered into this fixed size so
    /// textures align perfectly across an animation.
    static let canvasSize = CGSize(width: 180, height: 180)

    static func node(for pose: CookiePose, palette: CharacterPalette) -> SKNode {
        let root = SKNode()
        root.position = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

        let shadow = ellipse(CGSize(width: 74, height: 12), fill: SKColor.black.withAlphaComponent(0.08))
        shadow.position = CGPoint(x: 0, y: -72)
        shadow.zPosition = -3
        root.addChild(shadow)

        // Volume-ish preservation: squashing down widens the body.
        let character = SKNode()
        character.position = CGPoint(x: 0, y: pose.bodyY)
        character.xScale = 1 + (1 - pose.squash) * 0.7
        character.yScale = pose.squash
        character.zPosition = 1
        root.addChild(character)

        character.addChild(makeTail(angle: pose.tailAngle, palette: palette))
        character.addChild(makeBody(palette: palette))
        character.addChild(makePaws(pose: pose, palette: palette))
        character.addChild(makeHead(pose: pose, palette: palette))

        return root
    }

    // MARK: - Parts

    private static func makeTail(angle: CGFloat, palette: CharacterPalette) -> SKNode {
        let tail = SKNode()
        tail.position = CGPoint(x: 26, y: -20)
        tail.zRotation = angle * .pi / 180
        tail.zPosition = -2

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

    private static func makeBody(palette: CharacterPalette) -> SKNode {
        let body = outlinedEllipse(CGSize(width: 88, height: 72), fill: palette.fur, outline: palette.outline)
        body.position = CGPoint(x: 0, y: -26)
        return body
    }

    private static func makePaws(pose: CookiePose, palette: CharacterPalette) -> SKNode {
        let paws = SKNode()
        for side in [-1.0, 1.0] as [CGFloat] {
            let paw = outlinedEllipse(CGSize(width: 20, height: 13), fill: palette.fur, outline: palette.outline, width: 3.5)
            paw.position = CGPoint(x: side * 16 + pose.pawOffsetX, y: -58 + pose.pawLift)
            paw.zPosition = 1
            paws.addChild(paw)
        }
        return paws
    }

    private static func makeHead(pose: CookiePose, palette: CharacterPalette) -> SKNode {
        let head = SKNode()
        head.position = CGPoint(x: pose.headX, y: 30 + pose.headY)
        head.zRotation = pose.headTilt * .pi / 180
        head.zPosition = 2

        for side in [-1.0, 1.0] as [CGFloat] {
            let ear = SKNode()
            ear.position = CGPoint(x: side * 18, y: 36)
            ear.zPosition = 0
            let triangle = triangleShape(
                [CGPoint(x: side * 12, y: -14), CGPoint(x: side * 2, y: 16), CGPoint(x: side * -12, y: -6)],
                fill: palette.fur,
                outline: palette.outline
            )
            ear.addChild(triangle)
            let innerEar = triangleShape(
                [CGPoint(x: side * 6, y: -8), CGPoint(x: side * 1, y: 8), CGPoint(x: side * -7, y: -5)],
                fill: palette.innerEar,
                outline: nil
            )
            innerEar.alpha = 0.9
            ear.addChild(innerEar)
            if case .back = pose.earStyle {
                ear.zRotation = side * 0.55
                ear.position.y -= 4
            }
            head.addChild(ear)
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

        head.addChild(makeEyes(pose: pose, palette: palette))

        for side in [-1.0, 1.0] as [CGFloat] {
            let cheek = circle(radius: 8 * pose.blushScale, fill: palette.blush)
            cheek.alpha = 0.55
            cheek.position = CGPoint(x: side * 27, y: -8)
            cheek.zPosition = 2
            head.addChild(cheek)
        }

        head.addChild(makeMouth(pose: pose, palette: palette))

        for side in [-1.0, 1.0] as [CGFloat] {
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

    private static func makeEyes(pose: CookiePose, palette: CharacterPalette) -> SKNode {
        let eyes = SKNode()
        eyes.zPosition = 2
        let sides = [-1.0, 1.0] as [CGFloat]

        switch pose.eyeStyle {
        case .open, .wide:
            for side in sides {
                let size = pose.eyeStyle == .wide ? CGSize(width: 11, height: 14) : CGSize(width: 9, height: 12)
                let eye = ellipse(size, fill: palette.eye)
                eye.position = CGPoint(x: side * 15 + pose.gazeX, y: 2)
                eyes.addChild(eye)
                if pose.eyeStyle == .wide {
                    let glint = circle(radius: 2.5, fill: SKColor.white)
                    glint.position = CGPoint(x: side * 15 + pose.gazeX - 2, y: 4.5)
                    eyes.addChild(glint)
                }
            }
        case .half:
            for side in sides {
                let lid = lines([(CGPoint(x: side * 15 - 5, y: 5), CGPoint(x: side * 15 + 5, y: 5))], stroke: palette.eye, lineWidth: 2.5)
                let eye = ellipse(CGSize(width: 9, height: 6), fill: palette.eye)
                eye.position = CGPoint(x: side * 15 + pose.gazeX, y: 1)
                eyes.addChild(lid)
                eyes.addChild(eye)
            }
        case .happy:
            for side in sides {
                let eye = arc(center: CGPoint(x: side * 15, y: 2), radius: 8, startAngle: 0, endAngle: 180, stroke: palette.eye, lineWidth: 3)
                eyes.addChild(eye)
            }
        case .closed:
            for side in sides {
                let eye = arc(center: CGPoint(x: side * 15, y: 4), radius: 7, startAngle: 180, endAngle: 360, stroke: palette.eye, lineWidth: 3)
                eyes.addChild(eye)
            }
        }
        return eyes
    }

    private static func makeMouth(pose: CookiePose, palette: CharacterPalette) -> SKNode {
        let mouth = SKNode()
        mouth.zPosition = 2

        switch pose.mouthStyle {
        case .smile:
            for side in [-1.0, 1.0] as [CGFloat] {
                mouth.addChild(arc(center: CGPoint(x: side * 3.5, y: -9), radius: 4.5, startAngle: 180, endAngle: 360, stroke: palette.eye, lineWidth: 2.5))
            }
        case .flat:
            mouth.addChild(lines([(CGPoint(x: -6, y: -9), CGPoint(x: 6, y: -9))], stroke: palette.eye, lineWidth: 2.5))
        case .open:
            mouth.addChild(ellipse(CGSize(width: 8, height: 10), fill: palette.eye))
            mouth.children.last?.position = CGPoint(x: 0, y: -11)
        case .openWide:
            mouth.addChild(ellipse(CGSize(width: 13, height: 15), fill: palette.eye))
            mouth.children.last?.position = CGPoint(x: 0, y: -11)
            let tongue = ellipse(CGSize(width: 8, height: 7), fill: palette.innerEar)
            tongue.position = CGPoint(x: 0, y: -14)
            tongue.zPosition = 1
            mouth.addChild(tongue)
        }
        return mouth
    }

    // MARK: - Shape helpers

    private static func ellipse(_ size: CGSize, fill: SKColor) -> SKShapeNode {
        let node = SKShapeNode(ellipseOf: size)
        node.fillColor = fill
        node.strokeColor = .clear
        return node
    }

    private static func circle(radius: CGFloat, fill: SKColor) -> SKShapeNode {
        ellipse(CGSize(width: radius * 2, height: radius * 2), fill: fill)
    }

    private static func outlinedEllipse(_ size: CGSize, fill: SKColor, outline: SKColor, width: CGFloat = 4) -> SKShapeNode {
        let node = SKShapeNode(ellipseOf: size)
        node.fillColor = fill
        node.strokeColor = outline
        node.lineWidth = width
        return node
    }

    private static func triangleShape(_ points: [CGPoint], fill: SKColor, outline: SKColor?, width: CGFloat = 5) -> SKShapeNode {
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

    private static func arc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, stroke: SKColor, lineWidth: CGFloat) -> SKShapeNode {
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        let node = SKShapeNode(path: path.cgPath)
        node.strokeColor = stroke
        node.fillColor = .clear
        node.lineWidth = lineWidth
        node.lineCap = .round
        return node
    }

    private static func lines(_ segments: [(CGPoint, CGPoint)], stroke: SKColor, lineWidth: CGFloat) -> SKShapeNode {
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
