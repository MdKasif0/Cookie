import XCTest
@testable import Cookie

final class ReminderModelTests: XCTestCase {
    func testDueRemindersAreSplitOffSoonestFirst() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let later = CookieReminder(text: "later", dueAt: now.addingTimeInterval(60))
        let second = CookieReminder(text: "second", dueAt: now.addingTimeInterval(-10))
        let first = CookieReminder(text: "first", dueAt: now.addingTimeInterval(-100))
        let (due, waiting) = ReminderQueue.split([later, second, first], at: now)
        XCTAssertEqual(due.map(\.text), ["first", "second"])
        XCTAssertEqual(waiting.map(\.text), ["later"])
    }

    func testAnEmptyReminderIsATimer() {
        XCTAssertEqual(CookieReminder(text: "  ", dueAt: Date()).message, "Time's up!")
        XCTAssertEqual(CookieReminder(text: " Call Mom ", dueAt: Date()).message, "Call Mom")
    }

    func testLabels() {
        XCTAssertEqual(CookieReminder.label(forMinutes: 1), "1 minute")
        XCTAssertEqual(CookieReminder.label(forMinutes: 20), "20 minutes")
        XCTAssertEqual(CookieReminder.label(forMinutes: 60), "1 hour")
        XCTAssertEqual(CookieReminder.label(forMinutes: 90), "1.5 hours")
        let now = Date()
        XCTAssertEqual(CookieReminder(text: "", dueAt: now.addingTimeInterval(11 * 60 + 5)).remainingLabel(from: now), "in 12 min")
        XCTAssertEqual(CookieReminder(text: "", dueAt: now.addingTimeInterval(65 * 60)).remainingLabel(from: now), "in 1 h 05 min")
        XCTAssertEqual(CookieReminder(text: "", dueAt: now.addingTimeInterval(-5)).remainingLabel(from: now), "now")
    }
}

final class BreakNudgeScheduleTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 2_000_000)

    func testNothingIsDueBeforeItsInterval() {
        let schedule = BreakNudgeSchedule(start: start)
        XCTAssertNil(schedule.due(at: start.addingTimeInterval(19 * 60), enabled: [.eyes, .water]))
        XCTAssertEqual(schedule.due(at: start.addingTimeInterval(20 * 60), enabled: [.eyes, .water]), .eyes)
    }

    func testOnlyEnabledNudgesComeUp() {
        let schedule = BreakNudgeSchedule(start: start)
        XCTAssertNil(schedule.due(at: start.addingTimeInterval(50 * 60), enabled: [.water]))
        XCTAssertEqual(schedule.due(at: start.addingTimeInterval(60 * 60), enabled: [.water]), .water)
        XCTAssertNil(schedule.due(at: start.addingTimeInterval(3 * 3600), enabled: []))
    }

    func testTheMostOverdueWinsAndNudgesKeepTheirDistance() {
        var schedule = BreakNudgeSchedule(start: start)
        let t = start.addingTimeInterval(61 * 60)
        // Eyes is 41 minutes overdue, water 1 minute, posture 16.
        XCTAssertEqual(schedule.due(at: t, enabled: Set(BreakNudge.allCases)), .eyes)
        schedule.markShown(.eyes, at: t)
        XCTAssertNil(schedule.due(at: t.addingTimeInterval(4 * 60), enabled: Set(BreakNudge.allCases)))
        XCTAssertEqual(schedule.due(at: t.addingTimeInterval(5 * 60), enabled: Set(BreakNudge.allCases)), .posture)
    }

    func testRestartingPushesEverythingBack() {
        var schedule = BreakNudgeSchedule(start: start)
        let later = start.addingTimeInterval(2 * 3600)
        schedule.restart(at: later)
        XCTAssertNil(schedule.due(at: later.addingTimeInterval(10 * 60), enabled: Set(BreakNudge.allCases)))
    }

    func testMeetingAppsAreRecognised() {
        XCTAssertTrue(MeetingApps.isMeeting(bundleId: "us.zoom.xos"))
        XCTAssertTrue(MeetingApps.isMeeting(bundleId: "com.microsoft.teams2"))
        XCTAssertTrue(MeetingApps.isMeeting(bundleId: "com.apple.FaceTime"))
        XCTAssertFalse(MeetingApps.isMeeting(bundleId: "com.apple.Safari"))
        XCTAssertFalse(MeetingApps.isMeeting(bundleId: nil))
    }
}

final class BedtimeTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func testOnlyInsideTheWindowAfterBedtime() {
        let bedtime = 23 * 60
        XCTAssertFalse(Bedtime.shouldWindDown(now: date(20, 22, 59), minutes: bedtime, lastWindDown: nil, calendar: calendar))
        XCTAssertTrue(Bedtime.shouldWindDown(now: date(20, 23, 0), minutes: bedtime, lastWindDown: nil, calendar: calendar))
        // Past midnight still belongs to last night's bedtime.
        XCTAssertTrue(Bedtime.shouldWindDown(now: date(21, 1, 30), minutes: bedtime, lastWindDown: nil, calendar: calendar))
        // Three hours later the night is over.
        XCTAssertFalse(Bedtime.shouldWindDown(now: date(21, 2, 0), minutes: bedtime, lastWindDown: nil, calendar: calendar))
    }

    func testOncePerNight() {
        let bedtime = 23 * 60
        let shown = date(20, 23, 5)
        XCTAssertFalse(Bedtime.shouldWindDown(now: date(21, 0, 30), minutes: bedtime, lastWindDown: shown, calendar: calendar))
        XCTAssertTrue(Bedtime.shouldWindDown(now: date(21, 23, 1), minutes: bedtime, lastWindDown: shown, calendar: calendar))
    }

    func testABedtimeAfterMidnight() {
        let bedtime = 30   // 00:30
        XCTAssertFalse(Bedtime.shouldWindDown(now: date(20, 23, 50), minutes: bedtime, lastWindDown: nil, calendar: calendar))
        XCTAssertTrue(Bedtime.shouldWindDown(now: date(21, 0, 45), minutes: bedtime, lastWindDown: nil, calendar: calendar))
    }
}

@MainActor
final class HelpersControllerTests: XCTestCase {
    private var store: CookieStore!
    private var engine: CookieBehaviorEngine!
    private var said: [String] = []
    private var played: [SoundEffect] = []
    private var broughtOver = 0
    private var clock = Date(timeIntervalSince1970: 3_000_000)
    private var idle: TimeInterval = 0
    private var quiet = false
    private var focusing = false
    private var front: String? = "com.apple.Safari"

    override func setUp() async throws {
        store = CookieStore(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("helpers-\(UUID().uuidString).json"))
        store.profile.hasCompletedWelcome = true
        engine = CookieBehaviorEngine(store: store)
        said = []
        played = []
        broughtOver = 0
        idle = 0
        quiet = false
        focusing = false
        front = "com.apple.Safari"
    }

    private func makeController() -> HelpersController {
        let controller = HelpersController(
            store: store, engine: engine,
            say: { [unowned self] text, _ in said.append(text) },
            play: { [unowned self] effect in played.append(effect) },
            bringToCursor: { [unowned self] in broughtOver += 1 }
        )
        controller.now = { [unowned self] in clock }
        controller.idleSeconds = { [unowned self] in idle }
        controller.isQuiet = { [unowned self] in quiet }
        controller.isFocusing = { [unowned self] in focusing }
        controller.frontmostBundleId = { [unowned self] in front }
        return controller
    }

    func testAReminderComesToTheCursorAndIsSaidOnce() {
        let controller = makeController()
        controller.addReminder(text: "Call Mom", minutes: 20)
        XCTAssertEqual(store.profile.reminders.count, 1)
        said = []

        clock = clock.addingTimeInterval(19 * 60)
        controller.tick()
        XCTAssertTrue(said.isEmpty)

        clock = clock.addingTimeInterval(60)
        controller.tick()
        XCTAssertEqual(said, ["Call Mom"])
        XCTAssertEqual(broughtOver, 1)
        XCTAssertEqual(played, [.meow])
        XCTAssertTrue(store.profile.reminders.isEmpty)

        controller.tick()
        XCTAssertEqual(said.count, 1)
    }

    func testRemindersGetThroughEvenDuringQuietModeAndFocus() {
        quiet = true
        focusing = true
        let controller = makeController()
        controller.addReminder(text: "", minutes: 1)
        clock = clock.addingTimeInterval(61)
        controller.tick()
        XCTAssertEqual(said.last, "Time's up!")
    }

    func testCancellingAReminderStopsIt() {
        let controller = makeController()
        let reminder = controller.addReminder(text: "Tea", minutes: 5)
        controller.cancelReminder(id: reminder.id)
        clock = clock.addingTimeInterval(600)
        said = []
        controller.tick()
        XCTAssertTrue(said.isEmpty)
    }

    func testRemindersSurviveARelaunch() throws {
        store.profile.reminders = [CookieReminder(text: "Stretch", dueAt: clock.addingTimeInterval(300))]
        let data = try JSONEncoder().encode(store.profile)
        let decoded = try JSONDecoder().decode(CookieProfile.self, from: data)
        XCTAssertEqual(decoded.reminders.map(\.text), ["Stretch"])
    }

    func testNudgesComeWhenDueAndWaitForABetterMoment() {
        store.profile.settings.setNudge(.eyes, enabled: true)
        let controller = makeController()
        controller.start()
        controller.stop()
        said = []

        clock = clock.addingTimeInterval(20 * 60)
        quiet = true
        controller.tick()
        XCTAssertTrue(said.isEmpty, "Full-screen apps hold nudges back")

        quiet = false
        front = "us.zoom.xos"
        controller.tick()
        XCTAssertTrue(said.isEmpty, "Video calls hold nudges back")

        front = "com.apple.Safari"
        focusing = true
        controller.tick()
        XCTAssertTrue(said.isEmpty, "Focus sessions hold nudges back")

        focusing = false
        controller.tick()
        XCTAssertEqual(said.count, 1)
        controller.tick()
        XCTAssertEqual(said.count, 1)
    }

    func testSteppingAwayResetsTheNudgeClock() {
        store.profile.settings.setNudge(.eyes, enabled: true)
        let controller = makeController()
        controller.start()
        controller.stop()
        said = []

        clock = clock.addingTimeInterval(15 * 60)
        idle = 6 * 60
        controller.tick()
        idle = 0
        clock = clock.addingTimeInterval(10 * 60)
        controller.tick()
        XCTAssertTrue(said.isEmpty)
        clock = clock.addingTimeInterval(10 * 60)
        controller.tick()
        XCTAssertEqual(said.count, 1)
    }

    func testTheFocusGuardOnlyWatchesChosenAppsDuringASession() {
        store.profile.settings.distractingApps = [DistractingApp(bundleId: "com.valvesoftware.steam", name: "Steam")]
        let controller = makeController()

        controller.appDidSwitch(to: "com.valvesoftware.steam")
        XCTAssertTrue(said.isEmpty, "Not focusing")

        focusing = true
        controller.appDidSwitch(to: "com.apple.Safari")
        XCTAssertTrue(said.isEmpty, "Not on the list")

        controller.appDidSwitch(to: "com.valvesoftware.steam")
        XCTAssertEqual(said.count, 1)
        XCTAssertEqual(broughtOver, 1)

        controller.appDidSwitch(to: "com.valvesoftware.steam")
        XCTAssertEqual(said.count, 1, "Cooldown")
        clock = clock.addingTimeInterval(HelpersController.focusGuardCooldown)
        controller.appDidSwitch(to: "com.valvesoftware.steam")
        XCTAssertEqual(said.count, 2)

        store.profile.settings.focusGuardEnabled = false
        clock = clock.addingTimeInterval(HelpersController.focusGuardCooldown)
        controller.appDidSwitch(to: "com.valvesoftware.steam")
        XCTAssertEqual(said.count, 2)
    }

    func testBedtimeComesOnceAndOnlyWhenTurnedOn() {
        var calendar = Calendar.current
        calendar.timeZone = .current
        clock = calendar.date(bySettingHour: 23, minute: 15, second: 0, of: clock)!
        let controller = makeController()

        controller.tick()
        XCTAssertTrue(said.isEmpty, "Off by default")

        store.profile.settings.bedtimeEnabled = true
        controller.tick()
        XCTAssertEqual(said.count, 1)
        XCTAssertEqual(played.last, .sleep)
        XCTAssertNotNil(store.profile.lastBedtimeWindDown)

        clock = clock.addingTimeInterval(30 * 60)
        controller.tick()
        XCTAssertEqual(said.count, 1)
    }

    func testOlderSettingsDecodeWithHelpersOff() throws {
        let decoded = try JSONDecoder().decode(CookieSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(decoded.enabledBreakNudges.isEmpty)
        XCTAssertTrue(decoded.distractingApps.isEmpty)
        XCTAssertTrue(decoded.focusGuardEnabled)
        XCTAssertFalse(decoded.bedtimeEnabled)
        XCTAssertEqual(decoded.bedtimeMinutes, 23 * 60)
    }
}
