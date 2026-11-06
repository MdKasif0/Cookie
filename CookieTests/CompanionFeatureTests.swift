import XCTest
import CoreGraphics
@testable import Cookie

final class BondTests: XCTestCase {
    func testPointsComeFromAffectionAndVisitDays() {
        var stats = CookieStatistics()
        stats.affection = 12
        stats.visitDays = 3
        XCTAssertEqual(Bond.points(for: stats), 12 + 3 * Bond.visitDayPoints)
    }

    func testLevelsStartAtJustMetAndNeverSkipBackwards() {
        XCTAssertEqual(Bond.level(forPoints: 0).name, "Just Met")
        XCTAssertEqual(Bond.level(forPoints: 24).index, 0)
        XCTAssertEqual(Bond.level(forPoints: 25).index, 1)
        XCTAssertEqual(Bond.level(forPoints: 250).name, "Best Friends")
        XCTAssertEqual(Bond.level(forPoints: 100_000).index, Bond.levels.last?.index)
        XCTAssertEqual(Bond.levels.map(\.points), Bond.levels.map(\.points).sorted())
    }

    func testProgressTowardTheNextLevel() {
        let progress = Bond.progress(forPoints: 62)
        XCTAssertEqual(progress.level.index, 1)
        XCTAssertEqual(progress.next?.index, 2)
        XCTAssertEqual(progress.pointsToNext, 38)
        XCTAssertEqual(progress.fraction, 37.0 / 75.0, accuracy: 0.0001)

        let top = Bond.progress(forPoints: 9_999)
        XCTAssertNil(top.next)
        XCTAssertEqual(top.fraction, 1)
    }

    func testEveryItemIsUnlockedByExactlyOneLevel() {
        var seen: [String: Int] = [:]
        for level in Bond.levels {
            for item in level.unlocks { seen[item.id, default: 0] += 1 }
        }
        XCTAssertTrue(seen.values.allSatisfy { $0 == 1 })
    }

    func testEveryAccessoryCoatToyAndCozySpotIsAccountedFor() {
        let unlockable = Set(Bond.levels.flatMap(\.unlocks).map(\.id))
        for kind in AccessoryKind.allCases { XCTAssertTrue(unlockable.contains(BondItem.accessory(kind).id), kind.rawValue) }
        for kind in CozyKind.allCases { XCTAssertTrue(unlockable.contains(BondItem.cozy(kind).id), kind.rawValue) }
        for pattern in FurPattern.allCases where pattern != .none {
            XCTAssertTrue(unlockable.contains(BondItem.coat(pattern).id), pattern.rawValue)
        }
        // The starter toys, the plain coat and nothing else are free.
        let freeToys = ToyKind.allCases.filter { Bond.requiredLevel(for: .toy($0)) == nil }
        XCTAssertEqual(Set(freeToys), [.yarnBall, .ball, .box])
        XCTAssertNil(Bond.requiredLevel(for: .coat(.none)))
    }

    func testLockedItemsOpenAtTheirLevelOrWhenKept() {
        let crown = BondItem.accessory(.crown)
        XCTAssertFalse(Bond.isUnlocked(crown, points: 599))
        XCTAssertTrue(Bond.isUnlocked(crown, points: 600))
        XCTAssertTrue(Bond.isUnlocked(crown, points: 0, extra: [crown.id]))
        XCTAssertTrue(Bond.isUnlocked(.toy(.ball), points: 0))
    }

    func testNewUnlocksCoverEverySkippedLevel() {
        let items = Bond.newUnlocks(since: 0, points: 250)
        XCTAssertTrue(items.contains(.toy(.feather)))
        XCTAssertTrue(items.contains(.cozy(.bed)))
        XCTAssertTrue(items.contains(.cozy(.sunbeam)))
        XCTAssertFalse(items.contains(.accessory(.crown)))
        XCTAssertEqual(Bond.newUnlocks(since: 3, points: 250), [])
    }

    func testVisitsCountOncePerCalendarDay() {
        var stats = CookieStatistics()
        let calendar = Calendar(identifier: .gregorian)
        let morning = calendar.date(from: DateComponents(year: 2026, month: 3, day: 4, hour: 9))!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 3, day: 4, hour: 21))!
        let nextDay = calendar.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 8))!

        XCTAssertTrue(stats.recordVisit(now: morning, calendar: calendar))
        XCTAssertFalse(stats.recordVisit(now: evening, calendar: calendar))
        XCTAssertTrue(stats.recordVisit(now: nextDay, calendar: calendar))
        XCTAssertEqual(stats.visitDays, 2)
    }

    func testOldStatisticsFilesStillLoad() throws {
        let json = #"{"launchCount":4,"petsReceived":9,"affection":20}"#.data(using: .utf8)!
        let stats = try JSONDecoder().decode(CookieStatistics.self, from: json)
        XCTAssertEqual(stats.affection, 20)
        XCTAssertEqual(stats.visitDays, 0)
        XCTAssertEqual(stats.celebratedBondLevel, 0)
    }

    @MainActor
    func testLevelUpIsClaimedOnceAndRemembersItsItems() throws {
        let store = CookieStore(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("bond-\(UUID().uuidString).json"))
        store.statistics.affection = 120

        let first = try XCTUnwrap(store.claimBondLevelUp())
        XCTAssertEqual(first.level.index, 2)
        XCTAssertTrue(first.newItems.contains(.accessory(.glasses)))
        XCTAssertNil(store.claimBondLevelUp())
        XCTAssertTrue(store.profile.unlockedAccessories.contains(BondItem.cozy(.bed).id))
    }

    @MainActor
    func testWhatYouAlreadyWearStaysUnlocked() {
        let store = CookieStore(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("bond-\(UUID().uuidString).json"))
        var crown = store.profile.customization.accessory(for: .crown)
        crown.isEnabled = true
        store.profile.customization.setAccessory(crown)
        store.profile.customization.furPattern = .tabby

        XCTAssertFalse(store.isUnlocked(.accessory(.crown)))
        store.keepInUseItemsUnlocked()

        XCTAssertTrue(store.isUnlocked(.accessory(.crown)))
        XCTAssertTrue(store.isUnlocked(.coat(.tabby)))
        XCTAssertFalse(store.isUnlocked(.coat(.points)))
    }

    func testProfilesWithoutCozyItemsStillLoad() throws {
        let json = #"{"name":"Mochi"}"#.data(using: .utf8)!
        let profile = try JSONDecoder().decode(CookieProfile.self, from: json)
        XCTAssertEqual(profile.cozyItems, [])
        XCTAssertTrue(profile.settings.hideInFullscreen)
        XCTAssertEqual(profile.settings.summon, .controlOptionC)
    }
}

final class FocusTimerTests: XCTestCase {
    func testAFocusSessionRunsDownAndReportsItsLength() {
        var timer = FocusTimer()
        timer.startFocus(minutes: 25)

        XCTAssertEqual(timer.phase, .focusing)
        XCTAssertEqual(timer.remainingLabel, "25:00")
        XCTAssertNil(timer.advance(by: 60))
        XCTAssertEqual(timer.remainingLabel, "24:00")
        XCTAssertEqual(timer.progress, 1.0 / 25.0, accuracy: 0.0001)
        XCTAssertEqual(timer.advance(by: 24 * 60), .focusCompleted(minutes: 25))
        XCTAssertFalse(timer.isActive)
    }

    func testBreaksFinishWithTheirOwnEvent() {
        var timer = FocusTimer()
        timer.startBreak(minutes: 5)

        XCTAssertEqual(timer.phase, .onBreak)
        XCTAssertEqual(timer.advance(by: 301), .breakCompleted)
    }

    func testCancelledSessionsReportNothing() {
        var timer = FocusTimer()
        timer.startFocus(minutes: 15)
        _ = timer.advance(by: 600)

        timer.cancel()

        XCTAssertEqual(timer.phase, .idle)
        XCTAssertNil(timer.advance(by: 9_999))
    }

    func testSleepingThroughTheEndStillFinishesOnce() {
        var timer = FocusTimer()
        timer.startFocus(minutes: 10)

        XCTAssertEqual(timer.advance(by: 3 * 3600), .focusCompleted(minutes: 10))
        XCTAssertNil(timer.advance(by: 10))
    }

    func testLabelsRoundUpAndShowHours() {
        XCTAssertEqual(FocusTimer.format(0.2), "0:01")
        XCTAssertEqual(FocusTimer.format(65), "1:05")
        XCTAssertEqual(FocusTimer.format(3725), "1:02:05")
    }
}

final class DailyRhythmTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private func date(_ month: Int, _ day: Int, hour: Int = 12, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testSeasonsDressHer() {
        XCTAssertEqual(DailyRhythm.outfit(on: date(10, 31), firstMet: nil, calendar: calendar), [.pumpkin])
        XCTAssertEqual(DailyRhythm.outfit(on: date(12, 25), firstMet: nil, calendar: calendar), [.santaHat, .scarf])
        XCTAssertEqual(DailyRhythm.outfit(on: date(1, 20), firstMet: nil, calendar: calendar), [.scarf])
        XCTAssertEqual(DailyRhythm.outfit(on: date(6, 15), firstMet: nil, calendar: calendar), [])
        XCTAssertEqual(DailyRhythm.outfit(on: date(10, 23), firstMet: nil, calendar: calendar), [])
    }

    func testBirthdayNeedsAFullYearAndTheRightDay() {
        let met = date(3, 8, year: 2025)
        XCTAssertTrue(DailyRhythm.isBirthday(on: date(3, 8), firstMet: met, calendar: calendar))
        XCTAssertFalse(DailyRhythm.isBirthday(on: date(3, 9), firstMet: met, calendar: calendar))
        // The first week is not a birthday.
        XCTAssertFalse(DailyRhythm.isBirthday(on: date(3, 8, year: 2025), firstMet: met, calendar: calendar))
        XCTAssertEqual(DailyRhythm.outfit(on: date(3, 8), firstMet: met, calendar: calendar), [.hat])
    }

    func testBirthdayOutranksOtherHeadwear() {
        let met = date(12, 12, year: 2024)
        XCTAssertEqual(DailyRhythm.outfit(on: date(12, 12), firstMet: met, calendar: calendar), [.hat, .scarf])
    }

    func testWhatTheUserChoseAlwaysWins() {
        var config = CookieAppearanceConfig()
        var crown = config.accessory(for: .crown)
        crown.isEnabled = true
        config.setAccessory(crown)

        let dressed = config.withDailyOutfit(on: date(12, 25), firstMet: nil, calendar: calendar)

        XCTAssertFalse(dressed.accessory(for: .santaHat).isEnabled)
        XCTAssertTrue(dressed.accessory(for: .crown).isEnabled)
        XCTAssertTrue(dressed.accessory(for: .scarf).isEnabled)
    }

    func testTheOutfitNeverChangesTheStoredConfig() {
        let config = CookieAppearanceConfig()
        let dressed = config.withDailyOutfit(on: date(12, 25), firstMet: nil, calendar: calendar)

        XCTAssertTrue(dressed.accessory(for: .santaHat).isEnabled)
        XCTAssertFalse(config.accessory(for: .santaHat).isEnabled)
    }

    func testGreetingsFollowTheClock() {
        XCTAssertEqual(DailyRhythm.greeting(name: "Cookie", on: date(5, 5, hour: 8), firstMet: nil, calendar: calendar), "Good morning!")
        XCTAssertEqual(DailyRhythm.greeting(name: "Cookie", on: date(5, 5, hour: 19), firstMet: nil, calendar: calendar), "Good evening!")
        XCTAssertTrue(DailyRhythm.greeting(name: "Cookie", on: date(5, 5, hour: 23), firstMet: nil, calendar: calendar).contains("late"))
        let met = date(5, 5, year: 2024)
        XCTAssertEqual(DailyRhythm.greeting(name: "Cookie", on: date(5, 5, hour: 8), firstMet: met, calendar: calendar), "It's our birthday! 2 years together.")
    }
}

final class QuietModeTests: XCTestCase {
    private let display = CGRect(x: 0, y: 0, width: 1512, height: 982)

    func testAWindowCoveringTheWholeDisplayCountsAsFullscreen() {
        let window = WindowSnapshot(ownerPID: 200, layer: 0, bounds: display)
        XCTAssertTrue(FullscreenDetector.isFullscreenAppActive(windows: [window], displays: [display], ownPID: 1))
    }

    func testMaximizedWindowsBelowTheMenuBarDoNot() {
        let window = WindowSnapshot(ownerPID: 200, layer: 0, bounds: CGRect(x: 0, y: 38, width: 1512, height: 944))
        XCTAssertFalse(FullscreenDetector.isFullscreenAppActive(windows: [window], displays: [display], ownPID: 1))
    }

    func testDesktopAndSystemLayersAreIgnored() {
        let desktop = WindowSnapshot(ownerPID: 90, layer: -2147483623, bounds: display)
        let overlay = WindowSnapshot(ownerPID: 91, layer: 25, bounds: display)
        XCTAssertFalse(FullscreenDetector.isFullscreenAppActive(windows: [desktop, overlay], displays: [display], ownPID: 1))
    }

    func testCookieNeverHidesHerselfForHerOwnWindows() {
        let own = WindowSnapshot(ownerPID: 1, layer: 0, bounds: display)
        XCTAssertFalse(FullscreenDetector.isFullscreenAppActive(windows: [own], displays: [display], ownPID: 1))
    }

    func testEitherDisplayOfSeveralCanBeFullscreen() {
        let second = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        let window = WindowSnapshot(ownerPID: 200, layer: 0, bounds: second)
        XCTAssertTrue(FullscreenDetector.isFullscreenAppActive(windows: [window], displays: [display, second], ownPID: 1))
    }

    func testEveryShortcutHasAKeyExceptOff() {
        for shortcut in SummonShortcut.allCases {
            XCTAssertEqual(shortcut.keyCode == nil, shortcut == .off, shortcut.rawValue)
        }
        XCTAssertNotEqual(SummonShortcut.controlOptionC.carbonModifiers, SummonShortcut.commandOptionC.carbonModifiers)
    }
}

// MARK: - Engine, controllers and layout

@MainActor
final class FocusAndCozyEngineTests: XCTestCase {
    var store: CookieStore!
    var engine: CookieBehaviorEngine!
    var date: Date!

    override func setUp() {
        super.setUp()
        store = CookieStore(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("engine-\(UUID().uuidString).json"))
        engine = CookieBehaviorEngine(store: store)
        date = Date()
        engine.now = { [weak self] in self?.date ?? Date() }
        engine.visibleXRange = { 0...1440 }
        engine.start()
    }

    private func advance(_ seconds: TimeInterval, x: CGFloat = 500) {
        var remaining = seconds
        while remaining > 0 {
            let dt = min(remaining, 0.1)
            date = date.addingTimeInterval(dt)
            engine.tick(dt: dt, currentX: x, cursorX: nil)
            remaining -= dt
        }
    }

    func testFocusSettlesIntoANapAndStaysThere() {
        engine.beginFocus()
        XCTAssertEqual(engine.state, .yawning)
        XCTAssertTrue(engine.isFocusing)

        advance(5)
        XCTAssertEqual(engine.state, .sleeping)

        // However long it runs, she keeps napping instead of wandering off.
        advance(600)
        XCTAssertEqual(engine.state, .sleeping)
    }

    func testFinishingAFocusSessionStretchesMeowsAndSits() {
        engine.beginFocus()
        advance(5)

        engine.endFocus(completed: true)
        XCTAssertEqual(engine.state, .stretching)
        XCTAssertEqual(engine.reaction, .meow)
        XCTAssertFalse(engine.isFocusing)

        advance(2.3)
        XCTAssertEqual(engine.state, .reacting)
        advance(1.7)
        XCTAssertEqual(engine.state, .sitting)
    }

    func testCancellingJustWakesHerGently() {
        engine.beginFocus()
        advance(5)

        engine.endFocus(completed: false)

        XCTAssertEqual(engine.state, .stretching)
        XCTAssertNotEqual(engine.reaction, .meow)
        advance(2.3)
        XCTAssertEqual(engine.state, .sitting)
    }

    func testEndingWhenNotFocusingChangesNothing() {
        let before = engine.state
        engine.endFocus(completed: true)
        XCTAssertEqual(engine.state, before)
    }

    func testVisitingTheBedWalksOverThenNaps() {
        engine.visitCozy(.bed, atX: 800)
        XCTAssertEqual(engine.cozyVisit, .bed)
        XCTAssertEqual(engine.state, .curious)

        advance(1.0)
        XCTAssertEqual(engine.state, .walking)

        // Arriving within a few points of the bed starts the rest of the ritual.
        advance(0.3, x: 800)
        XCTAssertEqual(engine.state, .sitting)
        advance(1.7, x: 800)
        XCTAssertEqual(engine.state, .yawning)
        advance(2.3, x: 800)
        XCTAssertEqual(engine.state, .sleeping)
    }

    func testTheSessionEndsAndForgetsTheCozySpot() {
        engine.visitCozy(.scratchingPost, atX: 700)
        advance(1.0)
        advance(0.3, x: 700)
        XCTAssertEqual(engine.state, .stretching)

        advance(40, x: 700)
        XCTAssertNil(engine.cozyVisit)
    }

    func testGrabbingHerCancelsTheVisit() {
        engine.visitCozy(.sunbeam, atX: 900)
        engine.handleGrab()
        XCTAssertNil(engine.cozyVisit)
        XCTAssertEqual(engine.state, .beingDragged)
    }

    func testSummonMakesHerWaveAndCelebrationShowsLove() {
        advance(3)
        engine.summon()
        XCTAssertEqual(engine.activeEmote?.id, .wave)

        engine.cancelActiveEmote()
        advance(1)
        engine.celebrate()
        XCTAssertEqual(engine.activeEmote?.id, .love)
    }

    func testFocusStopsHerFromFollowingTheCursor() {
        engine.beginFocus()
        advance(5)
        for step in 0..<200 {
            date = date.addingTimeInterval(0.1)
            engine.tick(dt: 0.1, currentX: 500, cursorX: 520 + CGFloat(step % 3))
        }
        XCTAssertEqual(engine.state, .sleeping)
    }
}

@MainActor
final class FocusControllerTests: XCTestCase {
    private func makeParts() -> (CookieStore, CookieBehaviorEngine) {
        let store = CookieStore(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("focus-\(UUID().uuidString).json"))
        let engine = CookieBehaviorEngine(store: store)
        engine.start()
        return (store, engine)
    }

    func testASessionCountsDownThenStartsABreak() {
        let (store, engine) = makeParts()
        var said: [String] = []
        let controller = FocusController(store: store, engine: engine, say: { said.append($0) }, play: { _ in })
        var clock = Date(timeIntervalSince1970: 1_000_000)
        controller.now = { clock }
        store.profile.settings.breakMinutes = 5

        controller.startFocus(minutes: 10)
        XCTAssertTrue(engine.isFocusing)
        XCTAssertEqual(controller.statusTitle, "10:00")

        clock += 5 * 60
        controller.tick()
        XCTAssertEqual(controller.statusTitle, "5:00")

        clock += 5 * 60 + 1
        controller.tick()
        XCTAssertFalse(engine.isFocusing)
        XCTAssertEqual(store.statistics.focusSessions, 1)
        XCTAssertEqual(store.statistics.focusMinutes, 10)
        XCTAssertEqual(store.statistics.affection, 5)
        XCTAssertTrue(controller.isOnBreak)
        XCTAssertEqual(controller.statusTitle, "Break 5:00")
        XCTAssertTrue(said.last?.contains("Time for a break") == true)

        clock += 5 * 60 + 1
        controller.tick()
        XCTAssertEqual(controller.timer.phase, .idle)
        XCTAssertNil(controller.statusTitle)
        XCTAssertTrue(said.last?.contains("Break's over") == true)
        controller.stop()
    }

    func testStoppingEarlyRecordsNothing() {
        let (store, engine) = makeParts()
        let controller = FocusController(store: store, engine: engine, say: { _ in }, play: { _ in })
        controller.startFocus(minutes: 25)

        controller.stop()

        XCTAssertFalse(engine.isFocusing)
        XCTAssertEqual(store.statistics.focusSessions, 0)
        XCTAssertNil(controller.statusTitle)
    }

    func testSleepingThroughTheEndStillCompletesOnce() {
        let (store, engine) = makeParts()
        let controller = FocusController(store: store, engine: engine, say: { _ in }, play: { _ in })
        var clock = Date(timeIntervalSince1970: 2_000_000)
        controller.now = { clock }

        controller.startFocus(minutes: 25)
        clock += 4 * 3600
        controller.tick()
        controller.tick()

        XCTAssertEqual(store.statistics.focusSessions, 1)
        controller.stop()
    }

    func testStartingAgainDuringABreakBeginsANewSession() {
        let (store, engine) = makeParts()
        let controller = FocusController(store: store, engine: engine, say: { _ in }, play: { _ in })
        var clock = Date(timeIntervalSince1970: 3_000_000)
        controller.now = { clock }
        controller.startFocus(minutes: 5)
        clock += 301
        controller.tick()
        XCTAssertTrue(controller.isOnBreak)

        controller.startFocus(minutes: 15)

        XCTAssertTrue(controller.isFocusing)
        XCTAssertEqual(controller.statusTitle, "15:00")
        controller.stop()
    }
}

@MainActor
final class QuietModeMonitorTests: XCTestCase {
    private let display = CGRect(x: 0, y: 0, width: 1512, height: 982)

    func testFullscreenAppsQuietHerAndSummoningOverridesIt() {
        let store = CookieStore(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("quiet-\(UUID().uuidString).json"))
        let monitor = QuietModeMonitor(store: store)
        var windows: [WindowSnapshot] = []
        var clock = Date(timeIntervalSince1970: 5_000_000)
        monitor.windowSource = { windows }
        monitor.displaySource = { [display] in [display] }
        monitor.ownPID = 1
        monitor.now = { clock }

        monitor.evaluate()
        XCTAssertFalse(monitor.isQuiet)

        windows = [WindowSnapshot(ownerPID: 50, layer: 0, bounds: display)]
        monitor.evaluate()
        XCTAssertTrue(monitor.isQuiet)

        monitor.grantOverride(seconds: 20)
        XCTAssertFalse(monitor.isQuiet)

        clock += 21
        monitor.evaluate()
        XCTAssertTrue(monitor.isQuiet)
    }

    func testTurningTheSettingOffNeverQuietsHer() {
        let store = CookieStore(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("quiet-\(UUID().uuidString).json"))
        store.profile.settings.hideInFullscreen = false
        let monitor = QuietModeMonitor(store: store)
        monitor.windowSource = { [display] in [WindowSnapshot(ownerPID: 50, layer: 0, bounds: display)] }
        monitor.displaySource = { [display] in [display] }
        monitor.ownPID = 1

        monitor.evaluate()

        XCTAssertFalse(monitor.isQuiet)
    }

    func testTheRealWindowServerAnswersWithoutCrashing() {
        // On a real Mac these always return something; this guards the plumbing, not the answer.
        XCTAssertFalse(QuietModeMonitor.systemDisplays().isEmpty)
        _ = QuietModeMonitor.systemWindows()
    }
}

@MainActor
final class LayoutAndClockTests: XCTestCase {
    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testTheBubbleSitsOverHerHeadAndStaysOnScreen() {
        let size = CGSize(width: 200, height: 40)

        let centered = BubblePanelController.origin(bubbleSize: size, companionFrame: CGRect(x: 700, y: 100, width: 160, height: 160), visibleFrame: visible)
        XCTAssertEqual(centered.x, 680)
        XCTAssertEqual(centered.y, 246)

        let rightEdge = BubblePanelController.origin(bubbleSize: size, companionFrame: CGRect(x: 1380, y: 100, width: 160, height: 160), visibleFrame: visible)
        XCTAssertEqual(rightEdge.x, 1440 - 200 - 4)

        // No room above, so it drops beside her instead of off-screen.
        let top = BubblePanelController.origin(bubbleSize: size, companionFrame: CGRect(x: 700, y: 760, width: 160, height: 160), visibleFrame: visible)
        XCTAssertLessThan(top.y + size.height, 900)
    }

    func testSummonedCookieAppearsBesideTheCursorOnThatScreen() {
        let size = CGSize(width: 160, height: 160)

        let normal = WindowManager.summonOrigin(mouse: CGPoint(x: 500, y: 400), size: size, visible: visible)
        XCTAssertEqual(normal.x, 540)
        XCTAssertEqual(normal.y, 320)

        let nearEdge = WindowManager.summonOrigin(mouse: CGPoint(x: 1400, y: 400), size: size, visible: visible)
        XCTAssertEqual(nearEdge.x, 1200)

        let corner = WindowManager.summonOrigin(mouse: CGPoint(x: 10, y: 5), size: size, visible: visible)
        XCTAssertGreaterThanOrEqual(corner.y, 8)
    }

    func testNewCozyItemsKeepTheirDistance() {
        let primary = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let existing = [CozyPlacement(kind: .bed, position: 0.5)]

        let spot = WindowManager.newCozyPosition(preferredX: 500, primaryFrame: primary, existing: existing)

        XCTAssertGreaterThanOrEqual(abs(spot - 0.5), 0.11)
        XCTAssertEqual(WindowManager.newCozyPosition(preferredX: 300, primaryFrame: primary, existing: existing), 0.3, accuracy: 0.0001)
    }

    func testCozyPositionsAreFractionsOfTheMainScreen() {
        let primary = CGRect(x: 0, y: 0, width: 1500, height: 900)
        let placement = CozyPlacement(kind: .sunbeam, position: 0.4)

        let centerX = CozyPanelController.centerX(for: placement, primaryFrame: primary)

        XCTAssertEqual(centerX, 600)
        XCTAssertEqual(CozyPanelController.position(forCenterX: centerX, primaryFrame: primary), 0.4, accuracy: 0.0001)
        XCTAssertEqual(CozyPlacement(kind: .bed, position: 7).position, 0.96)
        XCTAssertEqual(CozyPlacement(kind: .bed, position: -2).position, 0.04)
    }

    func testPlacementsSurviveSavingAndLoading() throws {
        var profile = CookieProfile()
        profile.cozyItems = [CozyPlacement(kind: .bed, position: 0.3), CozyPlacement(kind: .scratchingPost, position: 0.8)]

        let data = try JSONEncoder().encode(profile)
        let loaded = try JSONDecoder().decode(CookieProfile.self, from: data)

        XCTAssertEqual(loaded.cozyItems, profile.cozyItems)
    }

    func testPlacingNeedsTheMatchingFriendshipLevel() {
        let store = CookieStore(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("cozy-\(UUID().uuidString).json"))
        XCTAssertFalse(store.isUnlocked(.cozy(.bed)))
        store.statistics.affection = 100
        XCTAssertTrue(store.isUnlocked(.cozy(.bed)))
        XCTAssertFalse(store.isUnlocked(.cozy(.sunbeam)))
    }

    func testEveryCozyItemHasArtAndAnIcon() {
        for kind in CozyKind.allCases {
            XCTAssertNotNil(CookieArtwork.image("Items", kind.assetName), kind.rawValue)
            XCTAssertNotNil(CookieArtwork.menuIcon(kind.iconName), kind.rawValue)
        }
    }

    func testTheDayClockTicksOverAtMidnight() {
        var now = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 4, hour: 23, minute: 58))!
        let clock = DailyClock(now: { now })
        let first = clock.day

        clock.check()
        XCTAssertEqual(clock.day, first)

        now = now.addingTimeInterval(4 * 60)
        clock.check()
        XCTAssertGreaterThan(clock.day, first)
    }
}

// MARK: - Photo mode

@MainActor
final class PhotoModeTests: XCTestCase {
    private let renderer = CookiePhotoRenderer()

    func testEveryPoseProducesFramesAtTheExportSize() throws {
        for pose in PhotoPose.all {
            let clip = try XCTUnwrap(renderer.clip(for: pose, config: CookieAppearanceConfig(), backdrop: .transparent), pose.id)
            XCTAssertGreaterThan(clip.frames.count, 1, pose.id)
            XCTAssertGreaterThan(clip.fps, 0, pose.id)
            for frame in clip.frames {
                XCTAssertEqual(frame.width, CookiePhotoRenderer.frameSide, pose.id)
                XCTAssertEqual(frame.height, CookiePhotoRenderer.frameSide, pose.id)
            }
        }
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return (data[0], data[1], data[2], data[3])
    }

    func testBackdropsFillTheCornersAndTransparentLeavesThemClear() throws {
        let frame = try XCTUnwrap(renderer.clip(for: PhotoPose.all[0], config: CookieAppearanceConfig(), backdrop: .transparent)?.frames.first)
        XCTAssertEqual(pixel(frame, x: 1, y: 1).a, 0)

        let cream = try XCTUnwrap(renderer.clip(for: PhotoPose.all[0], config: CookieAppearanceConfig(), backdrop: .cream)?.frames.first)
        let corner = pixel(cream, x: 1, y: 1)
        XCTAssertEqual(corner.a, 255)
        XCTAssertEqual(Int(corner.r), Int((0.98 * 255).rounded()), accuracy: 2)
    }

    func testAccessoriesAreDrawnOnBasePoses() throws {
        var dressed = CookieAppearanceConfig()
        var crown = dressed.accessory(for: .crown)
        crown.isEnabled = true
        dressed.setAccessory(crown)

        let plain = try XCTUnwrap(renderer.clip(for: PhotoPose.all[0], config: CookieAppearanceConfig(), backdrop: .cream)?.frames.first)
        let withCrown = try XCTUnwrap(renderer.clip(for: PhotoPose.all[0], config: dressed, backdrop: .cream)?.frames.first)

        // The crown sits near the top of her head, so some pixel there changes.
        var changed = false
        for y in stride(from: 20, to: 90, by: 4) {
            for x in stride(from: 150, to: 260, by: 4) where pixel(plain, x: x, y: y) != pixel(withCrown, x: x, y: y) { changed = true }
        }
        XCTAssertTrue(changed)
    }

    func testRepeatedEmoteFramesCollapseToOneCycle() {
        XCTAssertEqual(CookiePhotoRenderer.cycleLength(of: [1, 2, 3, 1, 2, 3, 1, 2, 3]), 3)
        XCTAssertEqual(CookiePhotoRenderer.cycleLength(of: [1, 2, 3]), 3)
        XCTAssertEqual(CookiePhotoRenderer.cycleLength(of: [7, 7, 7, 7]), 1)
        XCTAssertEqual(CookiePhotoRenderer.cycleLength(of: [1, 2, 1, 2, 1]), 5)
        XCTAssertEqual(CookiePhotoRenderer.cycleLength(of: [Int]()), 0)
    }

    func testEmoteGIFsAreOneCycleNotThree() throws {
        let wave = try XCTUnwrap(renderer.clip(for: PhotoPose.all[1], config: CookieAppearanceConfig(), backdrop: .cream))
        XCTAssertEqual(wave.frames.count, 10)
    }

    func testPNGDataIsARealPNG() throws {
        let frame = try XCTUnwrap(renderer.clip(for: PhotoPose.all[0], config: CookieAppearanceConfig(), backdrop: .transparent)?.frames.first)
        let data = try XCTUnwrap(CookiePhotoRenderer.pngData(frame))
        XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    func testGIFHasEveryFrameAndLoopsForever() throws {
        let clip = try XCTUnwrap(renderer.clip(for: PhotoPose.all[1], config: CookieAppearanceConfig(), backdrop: .transparent))
        let data = try XCTUnwrap(CookiePhotoRenderer.gifData(clip))

        XCTAssertEqual(String(decoding: data.prefix(6), as: UTF8.self), "GIF89a")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), clip.frames.count)
        let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        XCTAssertEqual(gif?[kCGImagePropertyGIFLoopCount] as? Int, 0)

        try data.write(to: URL(fileURLWithPath: "/tmp/cookie-photo-check-\(ProcessInfo.processInfo.processIdentifier).gif"))
    }

    func testTheModelOffersGIFOnlyForAnimatedPoses() {
        let store = CookieStore(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("photo-\(UUID().uuidString).json"))
        let model = PhotoModeModel(store: store)
        XCTAssertNotNil(model.clip)
        XCTAssertTrue(model.canSaveGIF)

        model.backdrop = .sky
        XCTAssertNotNil(model.clip)
    }
}

// MARK: - Parity with the Windows app

/// The Windows app keeps the same tables. These assert the same values as its tests, so one can't drift from the other.
final class PlatformParityTests: XCTestCase {
    func testUnlockIdsMatchTheWindowsTable() {
        let expected: [Int: [String]] = [
            1: ["toy.feather", "accessory.bow", "accessory.collar"],
            2: ["toy.toyMouse", "accessory.bandana", "accessory.glasses", "accessory.pumpkin", "coat.tabby", "cozy.bed"],
            3: ["toy.fishToy", "accessory.hat", "accessory.scarf", "accessory.santaHat", "coat.tuxedo", "cozy.sunbeam"],
            4: ["accessory.crown", "coat.points", "cozy.scratchingPost"]
        ]
        for (index, ids) in expected {
            XCTAssertEqual(Bond.levels[index].unlocks.map(\.id), ids, "Level \(index)")
        }
        XCTAssertEqual(Bond.levels.map(\.points), [0, 25, 100, 250, 600])
        XCTAssertEqual(Bond.levels.map(\.name), ["Just Met", "Friends", "Good Friends", "Best Friends", "Inseparable"])
    }

    @MainActor
    func testPhotoPosesMatchTheWindowsApp() {
        XCTAssertEqual(PhotoPose.all.map(\.id), ["idle", "wave", "happy", "love", "playful", "sleepy", "napping", "walk", "curious", "stretch"])
        XCTAssertEqual(PhotoPose.all.map(\.title), ["Sitting Pretty", "Hello!", "Happy", "In Love", "Playful", "Sleepy", "Napping", "On a Stroll", "Curious", "Big Stretch"])
    }

    func testOnlyTheModifierNamesDifferBetweenShortcutPresets() {
        // Windows offers Ctrl+Alt+C, Ctrl+Alt+Space and Ctrl+Shift+Alt+C; the Mac equivalents use Control and Option.
        XCTAssertEqual(SummonShortcut.controlOptionC.displayName, "⌃⌥C")
        XCTAssertEqual(SummonShortcut.controlOptionSpace.displayName, "⌃⌥Space")
        XCTAssertEqual(SummonShortcut.off.displayName, "Off")
    }

    func testFocusDefaultsMatch() {
        let settings = CookieSettings()
        XCTAssertEqual(settings.focusMinutes, 25)
        XCTAssertEqual(settings.breakMinutes, 5)
        XCTAssertTrue(settings.seasonalOutfits)
        XCTAssertTrue(settings.timeGreetings)
        XCTAssertTrue(settings.hideInFullscreen)
        XCTAssertTrue(settings.hideFromScreenSharing)
    }
}
