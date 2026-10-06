import SpriteKit

/// The character as the scene sees it: a single sprite node animated by
/// `SpriteAnimationController`, wrapped in a container that mirrors it
/// for direction. Artwork resolution (bundle sheets first, placeholder
/// frames second) lives entirely inside the controller.
final class CookieCharacterNode: SKNode, SpriteProviding {
    private(set) var activity: CookieActivity = .idle

    private let container = SKNode()
    private let sprite = SKSpriteNode()
    private let controller: SpriteAnimationController
    private var palette: CharacterPalette

    init(palette: CharacterPalette = .standard(for: .classicCream)) {
        self.palette = palette
        controller = SpriteAnimationController(
            sprite: sprite,
            flipContainer: container,
            palette: palette,
            sources: [SpriteSheetSource(), PlaceholderVectorSource()]
        )
        super.init()

        sprite.size = CookieSpriteRenderer.canvasSize
        container.addChild(sprite)
        addChild(container)
        controller.setBase(.idle)
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - SpriteProviding

    func startIdling() {
        activity = .idle
        controller.setBase(.idle)
    }

    func setActivity(_ newActivity: CookieActivity) {
        guard newActivity != activity else { return }
        activity = newActivity
        switch newActivity {
        case .idle:
            controller.setBase(.idle)
        case .sitting:
            controller.setBase(.sit)
        case .watching:
            controller.setBase(.curious)
        case .stretching:
            controller.play(.stretch)
        case .yawning:
            controller.play(.yawn)
        case .grooming:
            controller.play(.groom)
        case .delighted:
            controller.play(.pet)
        }
    }

    func playPetReaction() {
        activity = .delighted
        controller.play(.pet)
    }

    func apply(palette newPalette: CharacterPalette) {
        guard newPalette != palette else { return }
        palette = newPalette
        controller.updatePalette(newPalette)
        controller.refresh()
    }
}
