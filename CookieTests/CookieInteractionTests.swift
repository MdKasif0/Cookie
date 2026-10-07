import XCTest
@testable import Cookie

final class CookieInteractionTests: XCTestCase {
    var store: CookieStore!
    var engine: CookieBehaviorEngine!
    var simulatedDate: Date!

    @MainActor
    override func setUp() {
        super.setUp()
        store = CookieStore()
        engine = CookieBehaviorEngine(store: store)
        simulatedDate = Date()
        engine.now = { [weak self] in self?.simulatedDate ?? Date() }
        engine.visibleXRange = { 0...1440 }
        engine.start()
    }

    @MainActor
    func advanceTime(by seconds: TimeInterval, x: CGFloat = 500, cursorX: CGFloat? = nil) {
        let step: TimeInterval = 0.1
        var remaining = seconds
        while remaining > 0 {
            let dt = min(remaining, step)
            simulatedDate = simulatedDate.addingTimeInterval(dt)
            engine.tick(dt: dt, currentX: x, cursorX: cursorX)
            remaining -= dt
        }
    }

    // MARK: - Toy System Tests

    @MainActor
    func testOfferingToysInitializesSequence() {
        for toy in ToyKind.allCases {
            engine.handleOfferToy(toy)
            XCTAssertNotNil(engine.worldItem, "Offering \(toy.displayName) should spawn a worldItem")
            XCTAssertEqual(engine.state, .curious, "Offering \(toy.displayName) should start with Cookie noticing (.curious)")

            if toy == .box {
                XCTAssertTrue(engine.worldItem?.kind.isBox ?? false)
            } else {
                XCTAssertEqual(engine.worldItem?.kind, .toy(toy))
            }
        }
    }

    @MainActor
    func testToyLifecycleProgression() {
        engine.handleOfferToy(.yarnBall)
        XCTAssertEqual(engine.state, .curious)

        // Advance past notice phase to walking
        advanceTime(by: 2.0, x: 500)
        XCTAssertEqual(engine.state, .walking, "Cookie should walk toward the toy")

        // Reach the toy location
        let target = engine.worldItem!.x
        advanceTime(by: 0.2, x: target - 30) // within threshold
        XCTAssertEqual(engine.state, .investigating, "Cookie should investigate the toy upon arrival")

        // Advance through investigation to play
        advanceTime(by: 2.5, x: target - 30)
        XCTAssertEqual(engine.state, .playing, "Cookie should start playing with the toy")

        // Advance through play to tired
        advanceTime(by: 7.0, x: target - 30)
        XCTAssertEqual(engine.state, .tired, "Cookie should become tired after playing")
        XCTAssertGreaterThanOrEqual(store.statistics.toysPlayedWith, 1, "Toys played statistic should increment")

        // Advance through tired to sitting/idle
        advanceTime(by: 4.5, x: target - 30)
        XCTAssertTrue(engine.state == .sitting || engine.state == .idle, "Cookie should return to calm state")
    }

    // MARK: - Feeding Tests

    @MainActor
    func testFeedingLifecycleProgression() {
        for food in FoodKind.allCases {
            engine.handleFeed(food: food)
            XCTAssertNotNil(engine.worldItem)
            XCTAssertEqual(engine.worldItem?.kind, .food(food))
            XCTAssertEqual(engine.state, .curious)

            // Advance past notice to walk
            advanceTime(by: 1.5, x: 500)
            XCTAssertEqual(engine.state, .walking)

            // Arrive at food
            let target = engine.worldItem!.x
            advanceTime(by: 0.2, x: target - 30)
            XCTAssertEqual(engine.state, .investigating)

            // Advance to eating or drinking
            advanceTime(by: 2.0, x: target - 30)
            if food == .milk {
                XCTAssertEqual(engine.state, .drinking)
            } else {
                XCTAssertEqual(engine.state, .eating)
            }

            // Finish meal
            let previousTreats = store.statistics.treatsGiven
            advanceTime(by: 4.0, x: target - 30)
            XCTAssertGreaterThan(store.statistics.treatsGiven, previousTreats, "Treats given statistic should increment")
            XCTAssertEqual(engine.reaction, .happy, "Cookie should have a happy reaction after eating")
        }
    }

    // MARK: - Cardboard Box Tests

    @MainActor
    func testCardboardBoxLifecycle() {
        engine.handleOfferToy(.box)
        XCTAssertEqual(engine.state, .curious)
        XCTAssertTrue(engine.worldItem?.kind.isBox ?? false)

        // Walk to box
        advanceTime(by: 1.6, x: 500)
        XCTAssertEqual(engine.state, .walking)

        // Arrive at box
        let boxX = engine.worldItem!.x
        advanceTime(by: 0.2, x: boxX)
        XCTAssertEqual(engine.state, .investigating)

        // Enter box
        advanceTime(by: 2.5, x: boxX)
        XCTAssertEqual(engine.state, .inBox, "Cookie should enter the cardboard box")

        // Test peeking while in box
        // Advance time and check peeking toggle
        var witnessedPeek = false
        for _ in 0..<30 {
            advanceTime(by: 0.5, x: boxX)
            if engine.isPeeking {
                witnessedPeek = true
                break
            }
        }
        XCTAssertTrue(witnessedPeek, "Cookie should occasionally peek out of the box")

        // Petting box triggers peek immediately
        engine.handleClick(zone: nil)
        XCTAssertTrue(engine.isPeeking, "Clicking the box should make Cookie peek")

        // Wait until duration expires and Cookie exits box
        advanceTime(by: 35.0, x: boxX)
        XCTAssertTrue(engine.state != .inBox, "Cookie should exit the box")
        XCTAssertGreaterThanOrEqual(store.statistics.boxVisits, 1, "Box visits statistic should increment")
    }

    // MARK: - Seasonal & Special Accessories Tests

    func testSeasonalAccessoriesArchitecture() {
        let allKinds = AccessoryKind.allCases
        XCTAssertTrue(allKinds.contains(.scarf), "Winter scarf must exist")
        XCTAssertTrue(allKinds.contains(.hat), "Party hat must exist")
        XCTAssertTrue(allKinds.contains(.pumpkin), "Pumpkin must exist")
        XCTAssertTrue(allKinds.contains(.santaHat), "Santa hat must exist")
        XCTAssertTrue(allKinds.contains(.crown), "Crown must exist")

        XCTAssertEqual(AccessoryKind.scarf.theme, .winter)
        XCTAssertEqual(AccessoryKind.santaHat.theme, .holiday)
        XCTAssertEqual(AccessoryKind.pumpkin.theme, .autumn)
        XCTAssertEqual(AccessoryKind.hat.theme, .party)
        XCTAssertEqual(AccessoryKind.crown.theme, .party)

        XCTAssertTrue(AccessoryKind.scarf.isSeasonal)
        XCTAssertTrue(AccessoryKind.santaHat.isSeasonal)
        XCTAssertTrue(AccessoryKind.pumpkin.isSeasonal)
        XCTAssertFalse(AccessoryKind.collar.isSeasonal)

        // Verify config round trip
        var config = CookieAppearanceConfig()
        config.setAccessory(AccessoryConfig(kind: .pumpkin, isEnabled: true, scale: 1.1, offsetY: 0.02))
        config.setAccessory(AccessoryConfig(kind: .santaHat, isEnabled: true, scale: 0.9, offsetY: -0.01))

        XCTAssertTrue(config.accessory(for: .pumpkin).isEnabled)
        XCTAssertTrue(config.accessory(for: .santaHat).isEnabled)
    }

    // MARK: - Rare Special Events Tests

    @MainActor
    func testSpecialRandomEventsExecution() {
        for event in SpecialEventKind.allCases {
            engine.triggerSpecialEvent(event)
            switch event {
            case .zoomies:
                XCTAssertEqual(engine.state, .curious)
                advanceTime(by: 1.0, x: 500)
                XCTAssertEqual(engine.state, .running)
            case .toyChase:
                XCTAssertNotNil(engine.worldItem)
                XCTAssertEqual(engine.state, .curious)
            case .acrobatics:
                XCTAssertEqual(engine.state, .curious)
                advanceTime(by: 1.2, x: 500)
                XCTAssertEqual(engine.state, .special)
            case .unusualNap:
                XCTAssertEqual(engine.state, .walking)
            case .watchCursor:
                XCTAssertEqual(engine.state, .curious)
            case .boxAdventure:
                XCTAssertTrue(engine.worldItem?.kind.isBox ?? false)
            }
        }
    }

    // MARK: - Optionality & Non-Distracting Guarantees

    @MainActor
    func testWorldItemCanBeDismissedAnytime() {
        engine.handleOfferToy(.ball)
        XCTAssertNotNil(engine.worldItem)

        // User tidies up desk
        engine.clearWorldItem()
        XCTAssertNil(engine.worldItem, "Item must be cleared immediately when put away")
    }

    @MainActor
    func testItemPositionCanBeUpdatedOnDrag() {
        engine.handleOfferToy(.feather)
        let initialX = engine.worldItem!.x
        let newX = initialX + 80
        engine.updateWorldItemPosition(newX: newX)
        XCTAssertEqual(engine.worldItem?.x, newX, "Item x position should update when dragged")
    }
}
