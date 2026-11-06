import SpriteKit

/// Shows Cookie's accessories as rendered art over the character. Each image covers the
/// whole canvas and is already registered with the base pose, so it only needs to be
/// centered, then scaled and nudged around its anchor from the user's settings.
/// Layer order: neck pieces first, then head pieces, glasses last.
@MainActor
final class CookieAccessoryLayer: SKNode {
    static let drawOrder: [AccessoryKind] = [
        .scarf, .bandana, .collar, .bow, .hat, .pumpkin, .santaHat, .crown, .glasses
    ]

    func rebuild(for config: CookieAppearanceConfig) {
        removeAllChildren()
        let canvas = CookieSpriteRenderer.canvasSize

        for (order, kind) in Self.drawOrder.enumerated() {
            let accessory = config.accessory(for: kind)
            guard accessory.isEnabled,
                  let texture = CookieArtwork.texture("Accessories", kind.rawValue) else { continue }

            let node = SKSpriteNode(texture: texture, size: canvas)
            node.name = kind.rawValue
            let anchor = kind.anchor
            // Texture anchors count from the bottom-left; the character's origin is the canvas center.
            node.anchorPoint = CGPoint(x: anchor.x, y: 1 - anchor.y)
            node.position = CGPoint(
                x: (anchor.x - 0.5) * canvas.width,
                y: (0.5 - anchor.y) * canvas.height + accessory.offsetY * canvas.height
            )
            node.setScale(accessory.scale)
            node.zPosition = CGFloat(order) * 0.01
            addChild(node)
        }
    }
}
