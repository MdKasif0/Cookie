import SpriteKit

/// Supplies the frame textures for one animation. The animation system
/// consults an ordered chain of sources — bundle sprite sheets first,
/// the rendered placeholder second — and the first one that can supply
/// the animation wins. Shipping final artwork therefore requires no code
/// changes: add the sheets and they are picked up automatically.
@MainActor
protocol AnimationFrameSource {
    func textures(for animation: CookieAnimationId, palette: CharacterPalette) -> [SKTexture]?
}
