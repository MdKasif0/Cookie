import SpriteKit

/// Supplies the frame textures for one animation. The animation system
/// consults an ordered chain of sources — bundle sprite sheets first,
/// the rendered reference artwork second, the vector placeholder last —
/// and the first one that can supply the animation wins. Shipping final
/// artwork therefore requires no code changes: add the sheets and they
/// are picked up automatically.
///
/// Sources receive the full customization configuration; most ignore it,
/// but the reference-artwork source bakes fur color, patterns, eyes, and
/// body variation into its frames.
@MainActor
protocol AnimationFrameSource {
    func textures(for animation: CookieAnimationId, config: CookieAppearanceConfig) -> [SKTexture]?
}
