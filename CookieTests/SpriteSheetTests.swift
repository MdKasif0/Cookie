import XCTest
import SpriteKit
@testable import Cookie

@MainActor
final class SpriteSheetTests: XCTestCase {
    private let source = SpriteSheetSource()

    func testGeneratedSheetsLoadFromTheAppBundle() {
        let walk = source.textures(for: .walkRight, config: CookieAppearanceConfig(furColor: .warmWhite))
        XCTAssertEqual(walk?.count, 10)
        XCTAssertEqual(source.frameRate(for: .walkRight), 12)

        for animation in [CookieAnimationId.idle, .sleep, .stretch, .groom, .jump, .runLeft, .eat] {
            XCTAssertTrue(source.hasSheet(for: animation), "Missing sheet for \(animation)")
        }
    }

    func testLeftAndRightShareOneSheet() {
        XCTAssertEqual(
            source.textures(for: .walkLeft, config: CookieAppearanceConfig())?.count,
            source.textures(for: .walkRight, config: CookieAppearanceConfig())?.count
        )
    }

    func testFurColorIsBakedIntoSheetFrames() throws {
        let white = try XCTUnwrap(source.textures(for: .walkRight, config: CookieAppearanceConfig(furColor: .warmWhite))?.first)
        let brown = try XCTUnwrap(source.textures(for: .walkRight, config: CookieAppearanceConfig(furColor: .mutedBrown))?.first)

        XCTAssertGreaterThan(averageBrightness(white), averageBrightness(brown) * 1.4)
        XCTAssertEqual(white.size(), brown.size())
    }

    func testBaseArtAnimationsStepAsideForCoatAndEyeCustomization() {
        var patterned = CookieAppearanceConfig()
        patterned.furPattern = .tabby
        XCTAssertNil(source.textures(for: .idle, config: patterned))
        // Whole-pose art has its own painted coat and keeps playing.
        XCTAssertNotNil(source.textures(for: .walkRight, config: patterned))

        var customEyes = CookieAppearanceConfig()
        customEyes.eyeColor = .honey
        XCTAssertNil(source.textures(for: .sit, config: customEyes))
    }

    func testControllerFallsBackToReferenceArtForCustomCoats() {
        var patterned = CookieAppearanceConfig()
        patterned.furPattern = .tuxedo

        let sources: [AnimationFrameSource] = [source, ReferenceImageSource()]
        let frames = sources.compactMap { $0.textures(for: .idle, config: patterned) }.first

        XCTAssertEqual(frames?.count, 4, "The reference source's four-frame idle should take over")
    }

    func testWalkingPlaysAnimatedSheetInsteadOfStillSticker() {
        let node = CookieCharacterNode(config: CookieAppearanceConfig())
        node.setState(.walking, facing: .right, reaction: .happy)

        XCTAssertEqual(node.currentAnimationForTesting, .walkRight)
    }

    func testSleepingPlaysAnimatedSheetInsteadOfStillSticker() {
        let node = CookieCharacterNode(config: CookieAppearanceConfig())
        node.setState(.sleeping, facing: .right, reaction: .happy)

        XCTAssertEqual(node.currentAnimationForTesting, .sleep)
    }

    func testReactionsStillShowTheirExpressionStickers() {
        let node = CookieCharacterNode(config: CookieAppearanceConfig())
        node.setState(.reacting, facing: .right, reaction: .annoyed)

        XCTAssertNil(node.currentAnimationForTesting, "Stickers are not frame animations")
    }

    func testAccessoriesAreRegisteredOnTheCanvasCenteredOnTheCharacter() throws {
        var config = CookieAppearanceConfig()
        var hat = config.accessory(for: .hat)
        hat.isEnabled = true
        config.setAccessory(hat)

        let layer = CookieAccessoryLayer()
        layer.rebuild(for: config)

        let node = try XCTUnwrap(layer.childNode(withName: "hat") as? SKSpriteNode)
        // Scaled around its anchor, an unscaled image must still cover exactly the canvas.
        XCTAssertEqual(node.frame.midX, 0, accuracy: 0.01)
        XCTAssertEqual(node.frame.midY, 0, accuracy: 0.01)
        XCTAssertEqual(node.size, CookieSpriteRenderer.canvasSize)
    }

    func testEveryAccessoryHasArt() {
        for kind in AccessoryKind.allCases {
            XCTAssertNotNil(CookieArtwork.image("Accessories", kind.rawValue), kind.rawValue)
        }
    }

    func testEveryItemHasArtAndAnIcon() {
        for toy in ToyKind.allCases {
            XCTAssertNotNil(CookieArtwork.image("Items", toy.assetName), toy.rawValue)
            XCTAssertNotNil(CookieArtwork.menuIcon(toy.iconName), toy.rawValue)
        }
        for food in FoodKind.allCases {
            XCTAssertNotNil(CookieArtwork.image("Items", food.assetName), food.rawValue)
            XCTAssertNotNil(CookieArtwork.menuIcon(food.iconName), food.rawValue)
        }
        for name in ["box-front", "box-back", "food-empty"] {
            XCTAssertNotNil(CookieArtwork.image("Items", name), name)
        }
    }

    func testEveryEmoteHasAnIcon() {
        for id in EmoteId.allCases {
            XCTAssertNotNil(CookieArtwork.menuIcon("emote-\(id.rawValue)"), id.rawValue)
        }
    }

    func testMenuBarIconIsATemplate() throws {
        let image = try XCTUnwrap(NSImage(named: "CookieMenuBar"))
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size.width, 18)
    }

    func testEveryPersonalityCardHasFrames() {
        for personality in CookiePersonality.allCases {
            let sheet = personality.previewSheet
            let frames = CookieArtwork.frames(category: sheet.category, sheet: sheet.name)
            XCTAssertGreaterThan(frames?.images.count ?? 0, 1, personality.rawValue)
        }
    }

    func testWelcomeGreetingFollowsTheName() {
        let model = WelcomeViewModel(store: CookieStore()) { _, _ in }
        model.name = "Biscuit"
        XCTAssertEqual(model.greeting, "Hi, I'm Biscuit!")
        model.name = "   "
        XCTAssertEqual(model.greeting, "Hi, I'm Cookie!")
    }

    func testPurrIsALoopAndEveryTakeExists() throws {
        for effect in SoundEffect.allCases {
            for name in effect.fileNames {
                XCTAssertNotNil(Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Sounds"), name)
            }
        }
        let url = try XCTUnwrap(Bundle.main.url(forResource: "cookie-purr", withExtension: "wav", subdirectory: "Sounds"))
        XCTAssertGreaterThan(try XCTUnwrap(NSSound(contentsOf: url, byReference: true)).duration, 6)
    }

    private func averageBrightness(_ texture: SKTexture) -> Double {
        let image = texture.cgImage()
        let size = 32
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let context = CGContext(
            data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        var total = 0.0
        var counted = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) where pixels[index + 3] > 200 {
            total += Double(pixels[index]) + Double(pixels[index + 1]) + Double(pixels[index + 2])
            counted += 3
        }
        return counted > 0 ? total / counted : 0
    }
}
