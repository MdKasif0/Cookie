import SpriteKit

/// Anything that can render Cookie inside a scene. The placeholder chain
/// (bundle sheets → reference artwork → vector cat) sits behind this
/// protocol; the behavior engine speaks states, and conformers map states
/// onto animations.
@MainActor
protocol SpriteProviding: SKNode {
    var state: CookieState { get }
    func startIdling()
    func setState(_ state: CookieState, facing: CookieDirection, reaction: CookieReaction)
    func apply(config: CookieAppearanceConfig)
}
