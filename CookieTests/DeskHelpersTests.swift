import XCTest
@testable import Cookie

final class SystemWatchTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 4_000_000)
    let all = Set(SystemAlertKind.allCases)

    func testBatteryWarnsOnceAtLowThenAtCriticalAndReArmsAfterCharging() {
        var watch = SystemWatch()
        XCTAssertEqual(watch.update(with: SystemSnapshot(batteryPercent: 25), at: now, enabled: all), [])
        XCTAssertEqual(watch.update(with: SystemSnapshot(batteryPercent: 20), at: now, enabled: all), [.lowBattery(percent: 20)])
        XCTAssertEqual(watch.update(with: SystemSnapshot(batteryPercent: 15), at: now, enabled: all), [])
        XCTAssertEqual(watch.update(with: SystemSnapshot(batteryPercent: 9), at: now, enabled: all), [.criticalBattery(percent: 9)])
        XCTAssertEqual(watch.update(with: SystemSnapshot(batteryPercent: 8), at: now, enabled: all), [])
        // Plugging in re-arms it.
        _ = watch.update(with: SystemSnapshot(batteryPercent: 9, isCharging: true), at: now, enabled: all)
        XCTAssertEqual(watch.update(with: SystemSnapshot(batteryPercent: 18), at: now, enabled: all), [.lowBattery(percent: 18)])
    }

    func testDesktopsWithoutABatteryNeverWarn() {
        var watch = SystemWatch()
        XCTAssertEqual(watch.update(with: SystemSnapshot(batteryPercent: nil), at: now, enabled: all), [])
    }

    func testTheCPUHasToStayBusyForAWhile() {
        var watch = SystemWatch()
        for i in 0..<(SystemWatch.busySamples - 1) {
            XCTAssertEqual(watch.update(with: SystemSnapshot(cpuLoad: 1.2), at: now.addingTimeInterval(Double(i) * 20), enabled: all), [])
        }
        XCTAssertEqual(watch.update(with: SystemSnapshot(cpuLoad: 1.2), at: now.addingTimeInterval(200), enabled: all), [.cpuBusy])
        // Cooldown: no repeat for half an hour even if still busy.
        for i in 0..<20 {
            XCTAssertEqual(watch.update(with: SystemSnapshot(cpuLoad: 1.2), at: now.addingTimeInterval(220 + Double(i) * 20), enabled: all), [])
        }
    }

    func testABriefSpikeIsIgnored() {
        var watch = SystemWatch()
        for i in 0..<20 {
            let load = i % 5 == 0 ? 0.3 : 1.0
            XCTAssertEqual(watch.update(with: SystemSnapshot(cpuLoad: load), at: now.addingTimeInterval(Double(i) * 20), enabled: all), [])
        }
    }

    func testDiskWarnsAtMostOnceADay() {
        var watch = SystemWatch()
        let low = SystemSnapshot(diskFreeBytes: 6_000_000_000, diskTotalBytes: 500_000_000_000)
        XCTAssertEqual(watch.update(with: low, at: now, enabled: all), [.diskAlmostFull(freeGB: 6)])
        XCTAssertEqual(watch.update(with: low, at: now.addingTimeInterval(3600), enabled: all), [])
        XCTAssertEqual(watch.update(with: low, at: now.addingTimeInterval(25 * 3600), enabled: all), [.diskAlmostFull(freeGB: 6)])
        let fine = SystemSnapshot(diskFreeBytes: 200_000_000_000, diskTotalBytes: 500_000_000_000)
        var fresh = SystemWatch()
        XCTAssertEqual(fresh.update(with: fine, at: now, enabled: all), [])
    }

    func testNetworkDropAndReturn() {
        var watch = SystemWatch()
        XCTAssertEqual(watch.update(with: SystemSnapshot(isOnline: true), at: now, enabled: all), [])
        XCTAssertEqual(watch.update(with: SystemSnapshot(isOnline: false), at: now, enabled: all), [.offline])
        XCTAssertEqual(watch.update(with: SystemSnapshot(isOnline: false), at: now, enabled: all), [])
        XCTAssertEqual(watch.update(with: SystemSnapshot(isOnline: true), at: now, enabled: all), [.backOnline])
        // Starting offline isn't a drop.
        var fresh = SystemWatch()
        XCTAssertEqual(fresh.update(with: SystemSnapshot(isOnline: false), at: now, enabled: all), [])
    }

    func testTurnedOffKindsStaySilent() {
        var watch = SystemWatch()
        XCTAssertEqual(watch.update(with: SystemSnapshot(batteryPercent: 5), at: now, enabled: [.disk]), [])
        _ = watch.update(with: SystemSnapshot(isOnline: true), at: now, enabled: [])
        XCTAssertEqual(watch.update(with: SystemSnapshot(isOnline: false), at: now, enabled: []), [])
        XCTAssertEqual(watch.update(with: SystemSnapshot(isOnline: true), at: now, enabled: []), [], "No 'back online' without the 'offline'")
    }
}

final class CalendarHeadsUpTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 5_000_000)

    func testOnlyTimedEventsInsideTheLeadTimeNotYetAnnounced() {
        let standup = UpcomingEvent(id: "a", title: "Standup", start: now.addingTimeInterval(4 * 60 + 30))
        let lunch = UpcomingEvent(id: "b", title: "Lunch", start: now.addingTimeInterval(40 * 60))
        let holiday = UpcomingEvent(id: "c", title: "Holiday", start: now.addingTimeInterval(60), isAllDay: true)
        let past = UpcomingEvent(id: "d", title: "Earlier", start: now.addingTimeInterval(-60))
        let due = CalendarHeadsUp.eventsToAnnounce([lunch, holiday, standup, past], now: now, leadMinutes: 5, announced: [])
        XCTAssertEqual(due.map(\.title), ["Standup"])
        XCTAssertEqual(CalendarHeadsUp.message(for: standup, now: now), "Standup in 5 minutes.")

        let again = CalendarHeadsUp.eventsToAnnounce([standup], now: now, leadMinutes: 5, announced: [CalendarHeadsUp.key(for: standup)])
        XCTAssertTrue(again.isEmpty)
    }

    func testEachOccurrenceOfARepeatingMeetingIsSeparate() {
        let today = UpcomingEvent(id: "weekly", title: "Sync", start: now.addingTimeInterval(120))
        let nextWeek = UpcomingEvent(id: "weekly", title: "Sync", start: now.addingTimeInterval(7 * 86400 + 120))
        XCTAssertNotEqual(CalendarHeadsUp.key(for: today), CalendarHeadsUp.key(for: nextWeek))
    }

    func testMessages() {
        XCTAssertEqual(CalendarHeadsUp.message(for: UpcomingEvent(id: "x", title: "Call", start: now.addingTimeInterval(30)), now: now), "Call starts in a minute!")
        XCTAssertEqual(CalendarHeadsUp.message(for: UpcomingEvent(id: "x", title: " ", start: now.addingTimeInterval(600)), now: now), "Your next event in 10 minutes.")
    }
}

final class DownloadWatchTests: XCTestCase {
    func testAnnouncesNewFilesOnceTheyStopGrowing() {
        var watch = DownloadWatch()
        XCTAssertEqual(watch.update(with: ["old.zip": 10]), [], "What's already there is the baseline")
        XCTAssertEqual(watch.update(with: ["old.zip": 10, "movie.mp4.crdownload": 500]), [])
        XCTAssertEqual(watch.update(with: ["old.zip": 10, "movie.mp4": 900]), [])
        XCTAssertEqual(watch.update(with: ["old.zip": 10, "movie.mp4": 1000]), [], "Still growing")
        XCTAssertEqual(watch.update(with: ["old.zip": 10, "movie.mp4": 1000]), ["movie.mp4"])
        XCTAssertEqual(watch.update(with: ["old.zip": 10, "movie.mp4": 1000]), [])
    }

    func testAFileMovedAwayAndBackIsNoticedAgain() {
        var watch = DownloadWatch()
        _ = watch.update(with: ["a.pdf": 5])
        _ = watch.update(with: [:])
        _ = watch.update(with: ["a.pdf": 5])
        XCTAssertEqual(watch.update(with: ["a.pdf": 5]), ["a.pdf"])
    }

    func testPartialNames() {
        XCTAssertTrue(DownloadWatch.isPartial("x.crdownload"))
        XCTAssertTrue(DownloadWatch.isPartial("x.download"))
        XCTAssertTrue(DownloadWatch.isPartial("x.part"))
        XCTAssertTrue(DownloadWatch.isPartial(".DS_Store"))
        XCTAssertFalse(DownloadWatch.isPartial("report.pdf"))
        XCTAssertEqual(DownloadWatch.message(for: ["a"]), "Your download finished: a")
        XCTAssertEqual(DownloadWatch.message(for: ["a", "b"]), "2 downloads finished!")
    }
}

final class ScreenshotTidyTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 6_000_000)

    func testFindsOldScreenshotsOnly() {
        let old = now.addingTimeInterval(-2 * 86400)
        let files: [(name: String, modified: Date)] = [
            ("Screenshot 2026-11-01 at 10.00.00.png", old),
            ("Screen Shot 2020-01-01 at 9.00.00 AM.png", old),
            ("Screen Recording 2026-11-02 at 12.00.00.mov", old),
            ("Screenshot 2026-11-19 at 23.00.00.png", now.addingTimeInterval(-3600)),
            ("Holiday photo.png", old),
            ("Screenshot notes.txt", old),
        ]
        XCTAssertEqual(ScreenshotTidy.candidates(files, now: now), [
            "Screen Recording 2026-11-02 at 12.00.00.mov",
            "Screen Shot 2020-01-01 at 9.00.00 AM.png",
            "Screenshot 2026-11-01 at 10.00.00.png",
        ])
    }

    func testNamesNeverCollide() {
        XCTAssertEqual(ScreenshotTidy.uniqueName("a.png", existing: []), "a.png")
        XCTAssertEqual(ScreenshotTidy.uniqueName("a.png", existing: ["a.png"]), "a 2.png")
        XCTAssertEqual(ScreenshotTidy.uniqueName("a.png", existing: ["a.png", "a 2.png"]), "a 3.png")
    }

    func testTidyingMovesFilesIntoAFolderAndDeletesNothing() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tidy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let destination = folder.appendingPathComponent(ScreenshotTidy.folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: destination.appendingPathComponent("Screenshot 1.png"))
        try Data("new".utf8).write(to: folder.appendingPathComponent("Screenshot 1.png"))
        try Data("two".utf8).write(to: folder.appendingPathComponent("Screenshot 2.png"))

        XCTAssertEqual(DeskFiles.tidyScreenshots(["Screenshot 1.png", "Screenshot 2.png"], in: folder), 2)
        let moved = Set(try FileManager.default.contentsOfDirectory(atPath: destination.path))
        XCTAssertEqual(moved, ["Screenshot 1.png", "Screenshot 1 2.png", "Screenshot 2.png"])
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("Screenshot 1.png"), encoding: .utf8), "old")
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("Screenshot 1 2.png"), encoding: .utf8), "new")
    }
}

final class TaskRewardTests: XCTestCase {
    func testTasksEarnBondPointsUpToADailyCap() {
        var stats = CookieStatistics()
        let day = Date(timeIntervalSince1970: 7_000_000)
        for _ in 0..<CookieStatistics.rewardedTasksPerDay {
            XCTAssertTrue(stats.recordTaskCompleted(now: day))
        }
        XCTAssertFalse(stats.recordTaskCompleted(now: day))
        XCTAssertEqual(stats.tasksCompleted, CookieStatistics.rewardedTasksPerDay + 1)
        XCTAssertEqual(stats.affection, CookieStatistics.rewardedTasksPerDay * CookieStatistics.taskAffection)
        XCTAssertTrue(stats.recordTaskCompleted(now: day.addingTimeInterval(86400)))
    }
}

@MainActor
final class DeskControllerTests: XCTestCase {
    private var store: CookieStore!
    private var engine: CookieBehaviorEngine!
    private var said: [String] = []
    private var broughtOver = 0
    private var clock = Date(timeIntervalSince1970: 8_000_000)
    private var snapshot = SystemSnapshot()
    private var events: [UpcomingEvent] = []
    private var listing: [String: Int64] = [:]
    private var quiet = false
    private var screenshots: [String] = []
    private var movedScreenshots: [String] = []

    override func setUp() async throws {
        store = CookieStore(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("desk-\(UUID().uuidString).json"))
        store.profile.hasCompletedWelcome = true
        engine = CookieBehaviorEngine(store: store)
        said = []
        broughtOver = 0
        snapshot = SystemSnapshot()
        events = []
        listing = [:]
        quiet = false
        screenshots = []
        movedScreenshots = []
    }

    private func makeController() -> DeskController {
        let controller = DeskController(
            store: store, engine: engine,
            say: { [unowned self] text, _ in said.append(text) },
            play: { _ in },
            bringToCursor: { [unowned self] in broughtOver += 1 }
        )
        controller.now = { [unowned self] in clock }
        controller.isQuiet = { [unowned self] in quiet }
        controller.frontmostBundleId = { "com.apple.Safari" }
        controller.systemSnapshot = { [unowned self] in snapshot }
        controller.upcomingEvents = { [unowned self] _, _ in events }
        controller.downloadsListing = { [unowned self] in listing }
        controller.screenshotCandidates = { [unowned self] in (URL(fileURLWithPath: "/tmp"), screenshots) }
        controller.moveScreenshots = { [unowned self] names, _ in movedScreenshots = names; return names.count }
        return controller
    }

    func testLowBatteryWaitsForQuietModeButCriticalComesThrough() {
        let controller = makeController()
        quiet = true
        snapshot = SystemSnapshot(batteryPercent: 18)
        controller.checkSystem()
        XCTAssertTrue(said.isEmpty)

        snapshot = SystemSnapshot(batteryPercent: 7)
        controller.checkSystem()
        XCTAssertEqual(said.count, 1)
        XCTAssertTrue(said[0].contains("7%"))
        XCTAssertEqual(broughtOver, 1)
    }

    func testCalendarHeadsUpOnlyWhenTurnedOnAndOncePerEvent() {
        let controller = makeController()
        events = [UpcomingEvent(id: "s", title: "Standup", start: clock.addingTimeInterval(5 * 60))]
        controller.checkCalendar()
        XCTAssertTrue(said.isEmpty)

        store.profile.settings.calendarHeadsUp = true
        controller.checkCalendar()
        XCTAssertEqual(said, ["Standup in 5 minutes."])
        XCTAssertEqual(broughtOver, 1)
        controller.checkCalendar()
        XCTAssertEqual(said.count, 1)
    }

    func testDownloadsOnlyWhenTurnedOn() {
        let controller = makeController()
        listing = ["a.zip": 1]
        controller.checkDownloads()
        controller.checkDownloads()
        XCTAssertTrue(said.isEmpty)

        store.profile.settings.downloadAlerts = true
        controller.checkDownloads()  // baseline: a.zip is old news
        listing = ["a.zip": 1, "b.pdf": 3]
        controller.checkDownloads()
        controller.checkDownloads()
        XCTAssertEqual(said, ["Your download finished: b.pdf"])
    }

    func testScreenshotOfferIsOncePerDayAndNeedsAPile() {
        let controller = makeController()
        screenshots = (1...ScreenshotTidy.offerThreshold).map { "Screenshot \($0).png" }
        controller.checkScreenshots()
        XCTAssertTrue(said.isEmpty, "Off by default")
        XCTAssertEqual(controller.tidyableScreenshotCount(), 0, "Never looks while off")

        store.profile.settings.screenshotTidyOffers = true
        controller.checkScreenshots()
        XCTAssertEqual(said.count, 1)
        clock = clock.addingTimeInterval(3600)
        controller.checkScreenshots()
        XCTAssertEqual(said.count, 1)

        XCTAssertEqual(controller.tidyScreenshots(), ScreenshotTidy.offerThreshold)
        XCTAssertEqual(movedScreenshots.count, ScreenshotTidy.offerThreshold)
    }

    func testTodosTickOffAndEarnAffection() {
        let controller = makeController()
        XCTAssertFalse(controller.addTodo("   "))
        XCTAssertTrue(controller.addTodo("Water the plants"))
        let id = controller.todos[0].id
        let before = store.statistics.affection
        controller.toggleTodo(id: id)
        XCTAssertTrue(controller.todos[0].isDone)
        XCTAssertEqual(store.statistics.affection, before + CookieStatistics.taskAffection)
        XCTAssertEqual(store.statistics.tasksCompleted, 1)

        // Unticking doesn't take points back, and re-ticking counts toward the daily cap.
        controller.toggleTodo(id: id)
        XCTAssertFalse(controller.todos[0].isDone)
        controller.clearCompletedTodos()
        XCTAssertEqual(controller.todos.count, 1)
        controller.toggleTodo(id: id)
        controller.clearCompletedTodos()
        XCTAssertTrue(controller.todos.isEmpty)
    }

    func testTheListHasALimit() {
        let controller = makeController()
        for i in 0..<TodoItem.maximumCount { XCTAssertTrue(controller.addTodo("Task \(i)")) }
        XCTAssertFalse(controller.addTodo("One more"))
    }

    func testNotesAndTodosSurviveARelaunch() throws {
        store.profile.stickyNotes = [StickyNote(text: "Milk", color: .pink, origin: CGPoint(x: 10, y: 20))]
        store.profile.todos = [TodoItem(text: "Taxes")]
        let decoded = try JSONDecoder().decode(CookieProfile.self, from: JSONEncoder().encode(store.profile))
        XCTAssertEqual(decoded.stickyNotes.first?.text, "Milk")
        XCTAssertEqual(decoded.stickyNotes.first?.color, .pink)
        XCTAssertEqual(decoded.stickyNotes.first?.origin, CGPoint(x: 10, y: 20))
        XCTAssertEqual(decoded.todos.map(\.text), ["Taxes"])
    }

    func testOlderSettingsDecodeWithPermissionFeaturesOff() throws {
        let decoded = try JSONDecoder().decode(CookieSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded.enabledSystemAlerts, Set(SystemAlertKind.allCases))
        XCTAssertFalse(decoded.calendarHeadsUp)
        XCTAssertFalse(decoded.downloadAlerts)
        XCTAssertFalse(decoded.screenshotTidyOffers)
        XCTAssertTrue(decoded.showStickyNotes)
    }

    func testNotePlacementStaysOnScreen() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let nearRightEdge = StickyNotesController.origin(beside: CGRect(x: 900, y: 10, width: 90, height: 90), visible: visible, index: 0)
        XCTAssertLessThanOrEqual(nearRightEdge.x + StickyNotesController.size.width, visible.maxX)
        XCTAssertGreaterThanOrEqual(nearRightEdge.x, visible.minX)
        let middle = StickyNotesController.origin(beside: CGRect(x: 400, y: 10, width: 90, height: 90), visible: visible, index: 0)
        XCTAssertEqual(middle.x, 502)
    }
}
