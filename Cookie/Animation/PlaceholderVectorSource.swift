import SpriteKit

/// Renders the placeholder vector cat into frame textures, once per
/// (animation, palette), and caches them. This is the stand-in for the
/// final artwork: the same textures flow through the same controller a
/// sprite sheet would use, so the swap involves no architecture change.
@MainActor
final class PlaceholderVectorSource: AnimationFrameSource {
    @MainActor
    private static let renderView: SKView = {
        let view = SKView(frame: NSRect(origin: .zero, size: CookieSpriteRenderer.canvasSize))
        view.allowsTransparency = true
        return view
    }()

    private var cache: [String: [SKTexture]] = [:]

    func textures(for animation: CookieAnimationId, config: CookieAppearanceConfig) -> [SKTexture]? {
        let palette = CharacterPalette(config: config)
        let sheetName = animation.spec.sheetName
        guard let poses = CookiePoseCatalog.frames(forSheet: sheetName) else { return nil }

        let key = "\(config.renderKey)|\(sheetName)"
        if let cached = cache[key] {
            return cached
        }
        let textures = poses.map { pose in
            render(pose: pose, palette: palette)
        }
        cache[key] = textures
        return textures
    }

    /// Drops cached textures, e.g. when the palette changes.
    func invalidate() {
        cache.removeAll()
    }

    private func render(pose: CookiePose, palette: CharacterPalette) -> SKTexture {
        let scene = SKScene(size: CookieSpriteRenderer.canvasSize)
        scene.backgroundColor = .clear
        scene.scaleMode = .aspectFit
        scene.addChild(CookieSpriteRenderer.node(for: pose, palette: palette))
        return Self.renderView.texture(from: scene) ?? SKTexture()
    }
}
