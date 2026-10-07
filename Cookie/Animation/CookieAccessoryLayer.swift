import SpriteKit

/// Draws Cookie's accessories as crisp vector layers anchored to the
/// artwork, so they track the sprite perfectly at any size. Layer order:
/// neck pieces first, then head pieces, glasses last — nothing covers
/// Cookie's face incorrectly.
@MainActor
final class CookieAccessoryLayer: SKNode {
    func rebuild(for config: CookieAppearanceConfig) {
        removeAllChildren()
        let art = ReferenceImageSource.artRect(canvas: CookieSpriteRenderer.canvasSize)

        let order: [AccessoryKind] = [.scarf, .bandana, .collar, .bow, .hat, .pumpkin, .santaHat, .crown, .glasses]
        for kind in order {
            let accessory = config.accessory(for: kind)
            guard accessory.isEnabled, let node = makeNode(kind, art: art) else { continue }
            let anchor = kind.anchor
            node.position = CGPoint(
                x: art.minX + anchor.x * art.width,
                y: art.maxY - anchor.y * art.height + accessory.offsetY * art.height
            )
            node.setScale(accessory.scale)
            addChild(node)
        }
    }

    // MARK: - Builders

    /// All sizes derive from the art rect, so accessories scale with the
    /// sprite. Shapes are drawn around their anchor point.
    private func makeNode(_ kind: AccessoryKind, art: CGRect) -> SKNode? {
        let w = art.width, h = art.height
        switch kind {
        case .collar:
            let node = SKNode()
            let band = SKShapeNode(rectOf: CGSize(width: w * 0.30, height: h * 0.048), cornerRadius: h * 0.024)
            band.fillColor = SKColor(srgbRed: 0.91, green: 0.62, blue: 0.40, alpha: 1)
            band.strokeColor = SKColor(srgbRed: 0.55, green: 0.36, blue: 0.22, alpha: 1)
            band.lineWidth = 1.5
            node.addChild(band)
            let tag = SKShapeNode(circleOfRadius: w * 0.024)
            tag.fillColor = SKColor(srgbRed: 0.93, green: 0.78, blue: 0.44, alpha: 1)
            tag.strokeColor = SKColor(srgbRed: 0.62, green: 0.48, blue: 0.24, alpha: 1)
            tag.lineWidth = 1
            tag.position = CGPoint(x: 0, y: -h * 0.045)
            node.addChild(tag)
            return node

        case .bow:
            let node = SKNode()
            let color = SKColor(srgbRed: 0.66, green: 0.73, blue: 0.60, alpha: 1)
            let stroke = SKColor(srgbRed: 0.44, green: 0.50, blue: 0.38, alpha: 1)
            for side in [-1.0, 1.0] as [CGFloat] {
                let path = CGMutablePath()
                path.move(to: .zero)
                path.addLine(to: CGPoint(x: side * w * 0.052, y: -h * 0.024))
                path.addLine(to: CGPoint(x: side * w * 0.052, y: h * 0.024))
                path.closeSubpath()
                let wing = SKShapeNode(path: path)
                wing.fillColor = color
                wing.strokeColor = stroke
                wing.lineWidth = 1.5
                wing.lineJoin = .round
                node.addChild(wing)
            }
            let knot = SKShapeNode(circleOfRadius: w * 0.02)
            knot.fillColor = SKColor(srgbRed: 0.55, green: 0.62, blue: 0.48, alpha: 1)
            knot.strokeColor = stroke
            knot.lineWidth = 1
            node.addChild(knot)
            return node

        case .hat:
            let node = SKNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: -h * 0.115))
            path.addLine(to: CGPoint(x: -w * 0.055, y: h * 0.03))
            path.addLine(to: CGPoint(x: w * 0.055, y: h * 0.03))
            path.closeSubpath()
            let cone = SKShapeNode(path: path)
            cone.fillColor = SKColor(srgbRed: 0.94, green: 0.68, blue: 0.45, alpha: 1)
            cone.strokeColor = SKColor(srgbRed: 0.60, green: 0.40, blue: 0.24, alpha: 1)
            cone.lineWidth = 1.5
            node.addChild(cone)
            let pompom = SKShapeNode(circleOfRadius: w * 0.022)
            pompom.fillColor = SKColor(srgbRed: 0.98, green: 0.94, blue: 0.86, alpha: 1)
            pompom.strokeColor = SKColor(srgbRed: 0.78, green: 0.72, blue: 0.60, alpha: 1)
            pompom.lineWidth = 1
            pompom.position = CGPoint(x: 0, y: -h * 0.115)
            node.addChild(pompom)
            return node

        case .glasses:
            let node = SKNode()
            let lensColor = SKColor(srgbRed: 0.14, green: 0.13, blue: 0.12, alpha: 0.94)
            for side in [-1.0, 1.0] as [CGFloat] {
                let lens = SKShapeNode(rectOf: CGSize(width: w * 0.125, height: h * 0.072), cornerRadius: w * 0.03)
                lens.fillColor = lensColor
                lens.strokeColor = SKColor(srgbRed: 0.10, green: 0.09, blue: 0.09, alpha: 1)
                lens.lineWidth = 1.5
                lens.position = CGPoint(x: side * w * 0.083, y: 0)
                node.addChild(lens)
                let glint = SKShapeNode(circleOfRadius: w * 0.014)
                glint.fillColor = SKColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.55)
                glint.position = CGPoint(x: side * w * 0.083 + w * 0.02, y: h * 0.012)
                node.addChild(glint)
            }
            let bridge = SKShapeNode(rectOf: CGSize(width: w * 0.045, height: h * 0.008))
            bridge.fillColor = SKColor(srgbRed: 0.10, green: 0.09, blue: 0.09, alpha: 1)
            bridge.position = CGPoint(x: 0, y: h * 0.008)
            node.addChild(bridge)
            return node

        case .scarf:
            let node = SKNode()
            let band = SKShapeNode(rectOf: CGSize(width: w * 0.32, height: h * 0.05), cornerRadius: h * 0.024)
            band.fillColor = SKColor(srgbRed: 0.63, green: 0.70, blue: 0.58, alpha: 1)
            band.strokeColor = SKColor(srgbRed: 0.44, green: 0.50, blue: 0.38, alpha: 1)
            band.lineWidth = 1.5
            node.addChild(band)
            let tail = SKShapeNode(rectOf: CGSize(width: w * 0.065, height: h * 0.10), cornerRadius: w * 0.02)
            tail.fillColor = SKColor(srgbRed: 0.58, green: 0.65, blue: 0.53, alpha: 1)
            tail.strokeColor = SKColor(srgbRed: 0.44, green: 0.50, blue: 0.38, alpha: 1)
            tail.lineWidth = 1.2
            tail.position = CGPoint(x: w * 0.10, y: h * 0.068)
            tail.zRotation = 0.14
            node.addChild(tail)
            return node

        case .crown:
            let node = SKNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -w * 0.05, y: -h * 0.018))
            path.addLine(to: CGPoint(x: -w * 0.05, y: h * 0.038))
            path.addLine(to: CGPoint(x: -w * 0.025, y: h * 0.006))
            path.addLine(to: CGPoint(x: 0, y: h * 0.05))
            path.addLine(to: CGPoint(x: w * 0.025, y: h * 0.006))
            path.addLine(to: CGPoint(x: w * 0.05, y: h * 0.038))
            path.addLine(to: CGPoint(x: w * 0.05, y: -h * 0.018))
            path.closeSubpath()
            let crown = SKShapeNode(path: path)
            crown.fillColor = SKColor(srgbRed: 0.90, green: 0.73, blue: 0.32, alpha: 1)
            crown.strokeColor = SKColor(srgbRed: 0.64, green: 0.49, blue: 0.18, alpha: 1)
            crown.lineWidth = 1.5
            node.addChild(crown)
            let gem = SKShapeNode(circleOfRadius: w * 0.011)
            gem.fillColor = SKColor(srgbRed: 0.94, green: 0.62, blue: 0.45, alpha: 1)
            gem.position = CGPoint(x: 0, y: -h * 0.002)
            node.addChild(gem)
            return node

        case .bandana:
            let node = SKNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -w * 0.125, y: h * 0.012))
            path.addLine(to: CGPoint(x: w * 0.125, y: h * 0.012))
            path.addLine(to: CGPoint(x: 0, y: h * 0.10))
            path.closeSubpath()
            let triangle = SKShapeNode(path: path)
            triangle.fillColor = SKColor(srgbRed: 0.95, green: 0.73, blue: 0.55, alpha: 1)
            triangle.strokeColor = SKColor(srgbRed: 0.63, green: 0.44, blue: 0.28, alpha: 1)
            triangle.lineWidth = 1.5
            node.addChild(triangle)
            let knot = SKShapeNode(circleOfRadius: w * 0.016)
            knot.fillColor = SKColor(srgbRed: 0.91, green: 0.66, blue: 0.47, alpha: 1)
            knot.position = CGPoint(x: 0, y: h * 0.008)
            node.addChild(knot)
            return node

        case .pumpkin:
            let node = SKNode()
            let body = SKShapeNode(ellipseOf: CGSize(width: w * 0.16, height: h * 0.12))
            body.fillColor = SKColor(srgbRed: 0.94, green: 0.52, blue: 0.18, alpha: 1)
            body.strokeColor = SKColor(srgbRed: 0.68, green: 0.32, blue: 0.10, alpha: 1)
            body.lineWidth = 1.4
            node.addChild(body)

            for dx in [-1.0, 1.0] as [CGFloat] {
                let rib = SKShapeNode(ellipseOf: CGSize(width: w * 0.08, height: h * 0.115))
                rib.fillColor = .clear
                rib.strokeColor = SKColor(srgbRed: 0.78, green: 0.38, blue: 0.12, alpha: 0.7)
                rib.lineWidth = 1.0
                rib.position = CGPoint(x: dx * w * 0.035, y: 0)
                node.addChild(rib)
            }

            let stemPath = CGMutablePath()
            stemPath.move(to: CGPoint(x: -w * 0.012, y: h * 0.055))
            stemPath.addCurve(to: CGPoint(x: w * 0.018, y: h * 0.095),
                              control1: CGPoint(x: -w * 0.01, y: h * 0.08),
                              control2: CGPoint(x: w * 0.01, y: h * 0.09))
            stemPath.addLine(to: CGPoint(x: w * 0.008, y: h * 0.055))
            stemPath.closeSubpath()
            let stem = SKShapeNode(path: stemPath)
            stem.fillColor = SKColor(srgbRed: 0.38, green: 0.32, blue: 0.18, alpha: 1)
            stem.strokeColor = SKColor(srgbRed: 0.26, green: 0.20, blue: 0.10, alpha: 1)
            stem.lineWidth = 1
            node.addChild(stem)

            for side in [-1.0, 1.0] as [CGFloat] {
                let eye = SKShapeNode(rectOf: CGSize(width: w * 0.016, height: h * 0.016), cornerRadius: 1)
                eye.fillColor = SKColor(srgbRed: 0.98, green: 0.88, blue: 0.42, alpha: 0.95)
                eye.strokeColor = .clear
                eye.position = CGPoint(x: side * w * 0.032, y: h * 0.008)
                node.addChild(eye)
            }
            let smile = SKShapeNode(rectOf: CGSize(width: w * 0.045, height: h * 0.012), cornerRadius: 2)
            smile.fillColor = SKColor(srgbRed: 0.98, green: 0.88, blue: 0.42, alpha: 0.95)
            smile.strokeColor = .clear
            smile.position = CGPoint(x: 0, y: -h * 0.02)
            node.addChild(smile)
            return node

        case .santaHat:
            let node = SKNode()
            let conePath = CGMutablePath()
            conePath.move(to: CGPoint(x: -w * 0.075, y: -h * 0.01))
            conePath.addCurve(to: CGPoint(x: w * 0.075, y: h * 0.075),
                              control1: CGPoint(x: -w * 0.05, y: h * 0.08),
                              control2: CGPoint(x: w * 0.04, y: h * 0.09))
            conePath.addLine(to: CGPoint(x: w * 0.07, y: -h * 0.01))
            conePath.closeSubpath()
            let cone = SKShapeNode(path: conePath)
            cone.fillColor = SKColor(srgbRed: 0.88, green: 0.22, blue: 0.22, alpha: 1)
            cone.strokeColor = SKColor(srgbRed: 0.62, green: 0.14, blue: 0.14, alpha: 1)
            cone.lineWidth = 1.4
            node.addChild(cone)

            let brim = SKShapeNode(rectOf: CGSize(width: w * 0.16, height: h * 0.036), cornerRadius: h * 0.018)
            brim.fillColor = SKColor(srgbRed: 0.98, green: 0.98, blue: 0.96, alpha: 1)
            brim.strokeColor = SKColor(srgbRed: 0.82, green: 0.82, blue: 0.80, alpha: 1)
            brim.lineWidth = 1.2
            brim.position = CGPoint(x: 0, y: -h * 0.012)
            node.addChild(brim)

            let pompom = SKShapeNode(circleOfRadius: w * 0.024)
            pompom.fillColor = SKColor(srgbRed: 0.98, green: 0.98, blue: 0.96, alpha: 1)
            pompom.strokeColor = SKColor(srgbRed: 0.82, green: 0.82, blue: 0.80, alpha: 1)
            pompom.lineWidth = 1.2
            pompom.position = CGPoint(x: w * 0.078, y: h * 0.072)
            node.addChild(pompom)
            return node
        }
    }
}
