import XCTest
@testable import Cookie

final class HelpersTourTests: XCTestCase {
    func testTheTourCoversEachHelperAndEndsWithAWrapUp() {
        let steps = HelpersTour.steps(name: "Biscuit")
        XCTAssertEqual(steps.map(\.title), ["Reminders", "Notes and to-dos", "Drop files on me", "Chat with Biscuit", "That's the tour!"])
        XCTAssertEqual(steps.compactMap(\.action), [.newReminder, .pinNote, .openSettings])
        // A step with something to try names the button, and one without doesn't.
        for step in steps { XCTAssertEqual(step.tryTitle == nil, step.action == nil, step.title) }
        XCTAssertNil(steps.last?.action)
    }

    func testItStartsOnItsOwnOnlyOnceAndAtACalmMoment() {
        func can(welcome: Bool = true, seen: Bool = false, visible: Bool = true, quiet: Bool = false, focusing: Bool = false) -> Bool {
            HelpersTour.canStartOnItsOwn(hasCompletedWelcome: welcome, hasSeenTour: seen, isVisible: visible,
                                         isQuiet: quiet, isFocusing: focusing)
        }
        XCTAssertTrue(can())
        XCTAssertFalse(can(welcome: false), "not before she has been met")
        XCTAssertFalse(can(seen: true), "only once")
        XCTAssertFalse(can(visible: false), "not while she's hidden")
        XCTAssertFalse(can(quiet: true), "not over a full-screen app or in quiet mode")
        XCTAssertFalse(can(focusing: true), "not during a focus session")
    }

    func testProfilesFromBeforeTheTourHaveNotSeenItAndTheFlagIsSaved() throws {
        // An older profile has no field for the tour, so people who update see it once.
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CookieProfile())) as! [String: Any]
        old.removeValue(forKey: "hasSeenHelpersTour")
        let decoded = try JSONDecoder().decode(CookieProfile.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertFalse(decoded.hasSeenHelpersTour)

        var seen = CookieProfile()
        seen.hasSeenHelpersTour = true
        let roundTrip = try JSONDecoder().decode(CookieProfile.self, from: JSONEncoder().encode(seen))
        XCTAssertTrue(roundTrip.hasSeenHelpersTour)
    }

    func testTheCardSitsBesideHerAndStaysOnScreen() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let card = CGSize(width: 270, height: 150)
        // Room on the right: it goes there, level with her head.
        let right = TourPanelController.origin(cardSize: card, companionFrame: CGRect(x: 100, y: 100, width: 120, height: 120), visibleFrame: visible)
        XCTAssertEqual(right.x, 224)
        XCTAssertEqual(right.y, 70)
        // Against the right edge: it flips to her left.
        let left = TourPanelController.origin(cardSize: card, companionFrame: CGRect(x: 850, y: 100, width: 120, height: 120), visibleFrame: visible)
        XCTAssertEqual(left.x, 850 - 270 - 4)
        // Near the bottom: it's lifted to stay on screen.
        let low = TourPanelController.origin(cardSize: card, companionFrame: CGRect(x: 100, y: 0, width: 120, height: 60), visibleFrame: visible)
        XCTAssertEqual(low.y, 4)
    }
}
