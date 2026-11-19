import AppKit
import Combine

/// The everyday helpers: the system watcher, calendar heads-ups, the to-do list, the downloads
/// watcher and the screenshot tidy-up. Sticky notes have their own panels in `StickyNotesController`.
@MainActor
final class DeskController: ObservableObject {
    private let store: CookieStore
    private let engine: CookieBehaviorEngine
    private let say: (String, TimeInterval) -> Void
    private let play: (SoundEffect) -> Void
    private let bringToCursor: () -> Void

    private var ticker: Timer?
    private var tickCount = 0
    private var systemWatch = SystemWatch()
    private var downloads = DownloadWatch()
    private var announcedEvents: Set<String> = []
    private var downloadsWereOn = false

    // Seams for tests and for the real Mac.
    var now: () -> Date = { Date() }
    var isQuiet: () -> Bool = { false }
    var isFocusing: () -> Bool = { false }
    var frontmostBundleId: () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
    var systemSnapshot: () -> SystemSnapshot
    var upcomingEvents: (Date, Int) -> [UpcomingEvent]
    var downloadsListing: () -> [String: Int64] = {
        DeskFiles.downloadsFolder.map(DeskFiles.listing(of:)) ?? [:]
    }
    var screenshotCandidates: () -> (folder: URL, names: [String])? = { DeskFiles.screenshotCandidates() }
    var moveScreenshots: ([String], URL) -> Int = { DeskFiles.tidyScreenshots($0, in: $1) }

    let calendar = CalendarSource()
    private let probe = SystemProbe()

    init(store: CookieStore,
         engine: CookieBehaviorEngine,
         say: @escaping (String, TimeInterval) -> Void,
         play: @escaping (SoundEffect) -> Void,
         bringToCursor: @escaping () -> Void) {
        self.store = store
        self.engine = engine
        self.say = say
        self.play = play
        self.bringToCursor = bringToCursor
        let probe = self.probe
        let calendar = self.calendar
        self.systemSnapshot = { probe.snapshot() }
        self.upcomingEvents = { now, minutes in calendar.upcoming(from: now, minutes: minutes) }
    }

    func start() {
        guard ticker == nil else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        ticker?.tolerance = 1
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
    }

    // MARK: - The clock

    /// Every 5 seconds: downloads. Every 20: the system. Every 30: the calendar. Every 10 minutes:
    /// screenshots. Tests call the individual checks directly.
    func tick() {
        tickCount += 1
        checkDownloads()
        if tickCount % 4 == 0 { checkSystem() }
        if tickCount % 6 == 0 { checkCalendar() }
        if tickCount % 120 == 1 { checkScreenshots() }
    }

    private var canInterrupt: Bool {
        store.profile.isCompanionVisible
            && !isQuiet()
            && !MeetingApps.isMeeting(bundleId: frontmostBundleId())
    }

    // MARK: - System watcher

    func checkSystem() {
        let alerts = systemWatch.update(with: systemSnapshot(), at: now(), enabled: store.profile.settings.enabledSystemAlerts)
        guard let alert = alerts.first else { return }
        if alert.isUrgent {
            bringToCursor()
        } else if !canInterrupt {
            return
        }
        engine.react(alert == .backOnline ? .happy : .surprised)
        play(alert == .backOnline ? .happy : .surprise)
        say(alert.message(name: store.profile.displayName), alert.isUrgent ? 10 : 7)
    }

    // MARK: - Calendar

    /// A heads-up always gets through, like a reminder: being late for a meeting is worse than
    /// being interrupted in a full-screen app.
    func checkCalendar() {
        let settings = store.profile.settings
        guard settings.calendarHeadsUp else { return }
        let date = now()
        let due = CalendarHeadsUp.eventsToAnnounce(
            upcomingEvents(date, settings.calendarLeadMinutes),
            now: date, leadMinutes: settings.calendarLeadMinutes, announced: announcedEvents
        )
        guard !due.isEmpty else { return }
        due.forEach { announcedEvents.insert(CalendarHeadsUp.key(for: $0)) }
        if announcedEvents.count > 200 { announcedEvents = Set(due.map(CalendarHeadsUp.key(for:))) }
        bringToCursor()
        engine.summon()
        play(.chirp)
        say(due.map { CalendarHeadsUp.message(for: $0, now: date) }.joined(separator: "\n"), 10)
    }

    // MARK: - Downloads

    func checkDownloads() {
        guard store.profile.settings.downloadAlerts else {
            // Start fresh next time, so turning it on doesn't announce what is already there.
            if downloadsWereOn { downloads = DownloadWatch() }
            downloadsWereOn = false
            return
        }
        downloadsWereOn = true
        let finished = downloads.update(with: downloadsListing())
        guard !finished.isEmpty, canInterrupt, !isFocusing() else { return }
        engine.react(.happy)
        play(.chirp)
        say(DownloadWatch.message(for: finished), 5)
    }

    // MARK: - Screenshots

    /// At most once a day she mentions that screenshots have piled up.
    func checkScreenshots() {
        guard store.profile.settings.screenshotTidyOffers, canInterrupt, !isFocusing() else { return }
        let date = now()
        if let last = store.profile.lastScreenshotOffer, date.timeIntervalSince(last) < 24 * 3600 { return }
        guard let found = screenshotCandidates(), found.names.count >= ScreenshotTidy.offerThreshold else { return }
        store.profile.lastScreenshotOffer = date
        engine.react(.surprised)
        say(ScreenshotTidy.offer(count: found.names.count), 8)
    }

    /// Old screenshots waiting to be tidied, for the menu. Only looks when the feature is on,
    /// so the Desktop is never read otherwise.
    func tidyableScreenshotCount() -> Int {
        guard store.profile.settings.screenshotTidyOffers else { return 0 }
        return screenshotCandidates()?.names.count ?? 0
    }

    @discardableResult
    func tidyScreenshots() -> Int {
        guard let found = screenshotCandidates(), !found.names.isEmpty else {
            say("No old screenshots to tidy. Your desktop looks great!", 5)
            return 0
        }
        let moved = moveScreenshots(found.names, found.folder)
        if moved > 0 {
            engine.react(.happy)
            play(.happy)
            say("All tidy! I put \(moved) screenshot\(moved == 1 ? "" : "s") in the \(ScreenshotTidy.folderName) folder.", 6)
        } else {
            say("I couldn't move those screenshots. Check that Cookie can access that folder.", 6)
        }
        return moved
    }

    func revealScreenshotsFolder() {
        guard let folder = DeskFiles.screenshotFolder else { return }
        let destination = folder.appendingPathComponent(ScreenshotTidy.folderName, isDirectory: true)
        NSWorkspace.shared.activateFileViewerSelecting([FileManager.default.fileExists(atPath: destination.path) ? destination : folder])
    }

    // MARK: - To-do list

    var todos: [TodoItem] { store.profile.todos }

    @discardableResult
    func addTodo(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard store.profile.todos.filter({ !$0.isDone }).count < TodoItem.maximumCount else {
            say("That's a lot of tasks! Finish a few first?", 5)
            return false
        }
        store.profile.todos.append(TodoItem(text: String(trimmed.prefix(120)), createdAt: now()))
        objectWillChange.send()
        return true
    }

    /// Ticking a task off earns bond points (a few a day) and a little celebration.
    func toggleTodo(id: UUID) {
        guard let index = store.profile.todos.firstIndex(where: { $0.id == id }) else { return }
        store.profile.todos[index].isDone.toggle()
        let done = store.profile.todos[index].isDone
        store.profile.todos[index].doneAt = done ? now() : nil
        objectWillChange.send()
        guard done else { return }
        let rewarded = store.statistics.recordTaskCompleted(now: now())
        engine.react(.happy)
        play(rewarded ? .happy : .chirp)
        say(TodoItem.cheer(name: store.profile.displayName), 4)
    }

    func removeTodo(id: UUID) {
        store.profile.todos.removeAll { $0.id == id }
        objectWillChange.send()
    }

    func clearCompletedTodos() {
        store.profile.todos.removeAll(where: \.isDone)
        objectWillChange.send()
    }
}
