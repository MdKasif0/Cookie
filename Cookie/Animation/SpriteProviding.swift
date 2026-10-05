import SpriteKit

/// Anything that can render Cookie inside a scene. The placeholder cat is
/// a vector-drawn implementation; when the final sprite sheet arrives, a
/// new conformer (e.g. `AtlasSpriteProvider` backed by an SKTextureAtlas)
/// drops in without touching the scene, behavior, or persistence layers.
protocol SpriteProviding: SKNode {
    var activity: CookieActivity { get }
    func startIdling()
    func setActivity(_ activity: CookieActivity)
    func playPetReaction()
    func apply(palette: CharacterPalette)
}
