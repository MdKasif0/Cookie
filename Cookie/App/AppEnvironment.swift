import AppKit
import Combine
import ServiceManagement
import os

/// Composition root: builds the store, audio, behavior engine, and window
/// manager, wires them together, and drives the launch flow.
@MainActor
final class AppEnvironment: ObservableObject {
    let store: CookieStore
    let audioManager: AudioManager
    let behaviorEngine: CookieBehaviorEngine
    let windows: WindowManager
    let focus: FocusController
    let quietMode: QuietModeMonitor
    let helpers: HelpersController
    let desk: DeskController
    let clipboard: ClipboardController
    let fileDrop: FileDropController
    let chat: ChatController
    let summonHotKey = SummonHotKey()
    private(set) var menuBarController: MenuBarController?
    private var bondWatch: AnyCancellable?

    private let log = Logger(subsystem: "com.cookie.mac", category: "App")
    private var cancellables: Set<AnyCancellable> = []

    init() {
        #if DEBUG
        // For trying things without touching your real profile: COOKIE_STORE_PATH=/tmp/test.json
        let store = CookieStore(storageURL: ProcessInfo.processInfo.environment["COOKIE_STORE_PATH"].map { URL(fileURLWithPath: $0) })
        #else
        let store = CookieStore()
        #endif
        let audioManager = AudioManager(store: store)
        let behaviorEngine = CookieBehaviorEngine(store: store)
        let windows = WindowManager(store: store, audioManager: audioManager, behaviorEngine: behaviorEngine)
        self.store = store
        self.audioManager = audioManager
        self.behaviorEngine = behaviorEngine
        self.windows = windows
        self.focus = FocusController(
            store: store,
            engine: behaviorEngine,
            say: { [weak windows] text in windows?.say(text, seconds: 6) },
            play: { [weak audioManager] effect in audioManager?.play(effect) }
        )
        let quietMode = QuietModeMonitor(store: store)
        self.quietMode = quietMode
        let say: (String, TimeInterval) -> Void = { [weak windows] text, seconds in windows?.say(text, seconds: seconds) }
        let play: (SoundEffect) -> Void = { [weak audioManager] effect in audioManager?.play(effect) }
        let bringToCursor: () -> Void = { [weak windows, weak store, weak quietMode] in
            quietMode?.grantOverride(seconds: 20)
            if store?.profile.isCompanionVisible == false { store?.profile.isCompanionVisible = true }
            windows?.showCompanion()
            windows?.moveCompanionNearCursor()
        }
        self.helpers = HelpersController(store: store, engine: behaviorEngine, say: say, play: play, bringToCursor: bringToCursor)
        self.desk = DeskController(store: store, engine: behaviorEngine, say: say, play: play, bringToCursor: bringToCursor)
        self.clipboard = ClipboardController(store: store)
        self.fileDrop = FileDropController(store: store, engine: behaviorEngine, say: say, play: play)
        self.chat = ChatController(store: store, engine: behaviorEngine)
        windows.environment = self
        CookieCommandRouter.environment = self
        let fileDrop = self.fileDrop
        CompanionSKView.dropHandler = { [weak fileDrop] urls, view, point in
            guard let fileDrop, fileDrop.acceptsDrops else { return false }
            fileDrop.handleDrop(urls, in: view, at: point)
            return true
        }
        CompanionSKView.acceptsFileDrops = { [weak fileDrop] in fileDrop?.acceptsDrops ?? false }
        windows.menuProvider = { [weak self] in
            self?.createCookieMenu()
        }

        // Keep motion mode synchronized in real time
        store.$profile
            .map(\.settings.reducedMotion)
            .removeDuplicates()
            .sink { mode in
                MotionSettings.mode = mode
            }
            .store(in: &cancellables)

        // Observe macOS Accessibility Reduce Motion changes live
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                MotionSettings.mode = self.store.profile.settings.reducedMotion
            }
            .store(in: &cancellables)

        // Step aside for full-screen apps.
        quietMode.$isQuiet
            .removeDuplicates()
            .sink { [weak self] quiet in
                self?.windows.setQuiet(quiet)
                self?.audioManager.isMuted = quiet
            }
            .store(in: &cancellables)

        // The summon shortcut, and whether she shows up in screen sharing.
        summonHotKey.onTrigger = { [weak self] in self?.summonCookie() }
        store.$profile
            .map(\.settings.summonShortcut)
            .removeDuplicates()
            .sink { [weak self] raw in
                self?.summonHotKey.register(SummonShortcut(rawValue: raw) ?? .controlOptionC)
            }
            .store(in: &cancellables)
        store.$profile
            .map(\.settings.hideFromScreenSharing)
            .removeDuplicates()
            .sink { [weak self] hidden in self?.windows.setSharingHidden(hidden) }
            .store(in: &cancellables)

        // The menu bar counts down while a focus session runs.
        focus.$timer
            .sink { [weak self] _ in
                guard let self else { return }
                self.menuBarController?.updateStatusTitle(self.focus.statusTitle)
            }
            .store(in: &cancellables)

        // A new calendar day while she keeps running is another visit.
        DailyClock.shared.$day
            .dropFirst()
            .sink { [weak self] _ in self?.store.statistics.recordVisit() }
            .store(in: &cancellables)

        // Observe UpdateManager prompt visibility
        UpdateManager.shared.$isShowingUpdatePrompt
            .receive(on: DispatchQueue.main)
            .sink { [weak self] show in
                guard let self else { return }
                if show {
                    self.windows.showUpdatePrompt()
                } else {
                    self.windows.closeUpdatePrompt()
                }
            }
            .store(in: &cancellables)
    }

    /// Called once at launch. Returning users go straight to the desktop
    /// companion; first-time users meet Cookie in the welcome window.
    func start() {
        if menuBarController == nil {
            menuBarController = MenuBarController(environment: self, store: store)
        }
        store.statistics.recordLaunch()
        store.keepInUseItemsUnlocked()
        applySystemSettings()
        if store.profile.hasCompletedWelcome {
            log.info("Returning user — starting companion")
            if store.profile.settings.showOnStartup {
                windows.showCompanion()
            }
            behaviorEngine.start()
            startCompanionServices()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.greet() }
            // After her greeting has faded: people who updated from before the helpers get the tour once.
            DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak self] in self?.offerTourIfDue() }
        } else {
            presentWelcome()
        }

        // Check for updates in background if enabled, after a smooth launch pause
        if store.profile.settings.automaticallyCheckForUpdates {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.checkForUpdates(userInitiated: false)
            }
        }
    }

    // MARK: - Companion services

    private func startCompanionServices() {
        quietMode.start()
        DailyClock.shared.start()
        helpers.isQuiet = { [weak self] in self?.quietMode.isQuiet ?? false }
        helpers.isFocusing = { [weak self] in self?.focus.isFocusing ?? false }
        helpers.start()
        desk.isQuiet = { [weak self] in self?.quietMode.isQuiet ?? false }
        desk.isFocusing = { [weak self] in self?.focus.isFocusing ?? false }
        desk.start()
        clipboard.start()
        // Let her settle in before announcing anything.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.beginBondWatching() }
    }

    /// She says good morning, good evening or happy birthday when she first appears.
    private func greet() {
        let settings = store.profile.settings
        guard settings.timeGreetings, store.profile.isCompanionVisible, !quietMode.isQuiet else { return }
        windows.say(DailyRhythm.greeting(name: store.profile.displayName, on: Date(), firstMet: store.statistics.firstLaunchedAt), seconds: 5)
    }

    private func beginBondWatching() {
        celebrateBondLevelUp()
        bondWatch = store.$statistics
            .map(Bond.points(for:))
            .removeDuplicates()
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.celebrateBondLevelUp() }
    }

    /// A new friendship level: she celebrates and says what it unlocked.
    private func celebrateBondLevelUp() {
        guard let levelUp = store.claimBondLevelUp() else { return }
        behaviorEngine.celebrate()
        audioManager.play(.welcome)
        var text = "We're \(levelUp.level.name) now!"
        if !levelUp.newItems.isEmpty {
            let names = levelUp.newItems.prefix(3).map(\.displayName).joined(separator: ", ")
            let extra = levelUp.newItems.count - 3
            text += " Unlocked: \(names)" + (extra > 0 ? " and \(extra) more" : "")
        }
        windows.say(text, seconds: 8)
    }

    /// Calls Cookie to the cursor and has her wave hello. It overrides full-screen hiding briefly.
    func summonCookie() {
        // Calling her ends quiet mode you set yourself.
        if quietMode.isManuallyQuiet { quietMode.setManualQuiet(false) }
        quietMode.grantOverride(seconds: 20)
        if !store.profile.isCompanionVisible { store.profile.isCompanionVisible = true }
        windows.showCompanion()
        windows.moveCompanionNearCursor()
        behaviorEngine.summon()
        audioManager.play(.chirp)
    }

    /// Syncs settings that touch the system: launch-at-login state and
    /// the reduced-motion mode.
    private func applySystemSettings() {
        MotionSettings.mode = store.profile.settings.reducedMotion
        if SMAppService.mainApp.status == .enabled, !store.profile.settings.launchAtLogin {
            // macOS knows better (registered outside the app) — follow it.
            store.profile.settings.launchAtLogin = true
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        store.profile.settings.launchAtLogin = enabled
        guard SMAppService.mainApp.status != .notFound else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("Launch-at-login toggle failed: \(error.localizedDescription)")
        }
    }

    func completeWelcome(name: String, personality: CookiePersonality) {
        store.profile.name = name
        store.profile.personality = personality
        store.profile.hasCompletedWelcome = true
        windows.closeWelcome()
        windows.showCompanion()
        behaviorEngine.start()
        startCompanionServices()
        audioManager.play(.welcome)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.offerTourIfDue() }
    }

    // MARK: - Helpers tour

    /// From her menu: always available, and brings her back on screen if she was hidden.
    func startHelpersTour() {
        configureTour()
        if !store.profile.isCompanionVisible { toggleCompanion() }
        windows.startTour(steps: HelpersTour.steps(name: store.profile.displayName))
    }

    /// Starts the tour by itself only once, and only at a calm moment; otherwise it waits for another launch.
    private func offerTourIfDue() {
        guard HelpersTour.canStartOnItsOwn(
            hasCompletedWelcome: store.profile.hasCompletedWelcome,
            hasSeenTour: store.profile.hasSeenHelpersTour,
            isVisible: store.profile.isCompanionVisible,
            isQuiet: quietMode.isQuiet,
            isFocusing: focus.isFocusing
        ) else { return }
        configureTour()
        windows.startTour(steps: HelpersTour.steps(name: store.profile.displayName))
    }

    private func configureTour() {
        let tour = windows.tour
        guard tour.onEnd == nil else { return }
        tour.onStepShown = { [weak self] step in
            self?.behaviorEngine.react(step.reaction)
            self?.audioManager.play(.chirp)
        }
        tour.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .newReminder: self.windows.showNewReminder()
            case .pinNote: self.windows.addStickyNote(text: HelpersTour.sampleNote)
            case .openSettings: self.windows.showSettings(tab: .powerTools)
            }
        }
        tour.onEnd = { [weak self] finished in
            guard let self else { return }
            self.store.profile.hasSeenHelpersTour = true
            if finished {
                self.behaviorEngine.celebrate()
                self.audioManager.play(.happy)
            }
        }
    }

    /// The welcome window was closed without continuing: start Cookie with
    /// the current (default) settings so the app is still usable.
    private func handleWelcomeDismissed() {
        guard !store.profile.hasCompletedWelcome else { return }
        store.profile.hasCompletedWelcome = true
        windows.showCompanion()
        behaviorEngine.start()
        startCompanionServices()
    }

    /// Full reset from Settings: back to a fresh first run.
    func resetCookie() {
        windows.tour.end(finished: false)
        helpers.stop()
        desk.stop()
        behaviorEngine.stop()
        store.reset()
        presentWelcome()
    }

    func toggleCompanion() {
        windows.toggleCompanion()
    }

    func showCustomization() {
        windows.showCustomization()
    }

    func showSettings() {
        windows.showSettings()
    }

    // Menu bar companion commands.
    func petCookie() { behaviorEngine.handleMenuPet() }
    func feedCookie(food: FoodKind? = nil) { behaviorEngine.handleFeed(food: food) }
    func offerToy(_ toy: ToyKind) { behaviorEngine.handleOfferToy(toy) }
    func playWithCookie() { behaviorEngine.handlePlayCommand() }
    func clearWorldItem() { behaviorEngine.clearWorldItem() }
    var hasActiveWorldItem: Bool { behaviorEngine.worldItem != nil }
    func triggerSpecialEvent(_ event: SpecialEventKind) { behaviorEngine.triggerSpecialEvent(event) }
    @discardableResult
    func triggerEmote(_ emote: Emote) -> Bool { behaviorEngine.triggerEmote(emote) }
    func showEmotePicker() { windows.showEmotePicker() }
    func showPhotoMode() { windows.showPhotoMode() }

    // Focus, cozy corner and friendship
    func startFocus(minutes: Int? = nil) { focus.startFocus(minutes: minutes) }
    func stopFocus() { focus.stop() }
    func placeCozy(_ kind: CozyKind) { windows.placeCozy(kind) }
    func removeCozy(_ kind: CozyKind) { windows.removeCozy(kind) }
    func isUnlocked(_ item: BondItem) -> Bool { store.isUnlocked(item) }

    // Reminders and timers
    func addReminder(text: String, minutes: Int) { helpers.addReminder(text: text, minutes: minutes) }
    func cancelReminder(id: UUID) { helpers.cancelReminder(id: id) }
    func showNewReminder() { windows.showNewReminder() }

    // Sticky notes
    func showNewStickyNote() {
        windows.showTextPrompt(title: "New Sticky Note", placeholder: "Buy milk, call the bank…", actionTitle: "Pin It",
                               multiline: true, maximumLength: StickyNote.maximumLength) { [weak self] text in
            self?.windows.addStickyNote(text: text)
        }
    }

    // Power tools
    func showAskCookie() { windows.showAskCookie(chat: chat) }

    func setQuiet(_ on: Bool, minutes: Int? = nil) {
        quietMode.setManualQuiet(on, minutes: minutes)
    }

    /// Runs a command from a `cookie://` link or a Shortcuts action.
    func perform(_ command: CookieCommand) {
        guard store.profile.settings.allowLinks else {
            log.notice("Ignored a link or Shortcuts command: they're turned off in Settings")
            return
        }
        switch command {
        case .say(let text):
            windows.say(text, seconds: max(4, min(12, Double(text.count) / 12)))
        case .remind(let text, let minutes):
            helpers.addReminder(text: text, minutes: minutes)
        case .startFocus(let minutes):
            focus.startFocus(minutes: minutes)
        case .stopFocus:
            focus.stop()
        case .quiet(let on, let minutes):
            setQuiet(on, minutes: minutes)
        case .toggleQuiet:
            setQuiet(!quietMode.isManuallyQuiet)
        case .show:
            if !store.profile.isCompanionVisible { toggleCompanion() }
        case .hide:
            if store.profile.isCompanionVisible { toggleCompanion() }
        case .summon:
            summonCookie()
        case .pet:
            petCookie()
        case .emote(let id):
            triggerEmote(Emote.find(id))
        case .addTodo(let text):
            if desk.addTodo(text) { windows.say("Added to your list!", seconds: 3) }
        case .addNote(let text):
            windows.addStickyNote(text: text)
        case .ask:
            showAskCookie()
        }
    }

    /// `cookie://` links, from `open`, Raycast, a browser or a script.
    func handle(urls: [URL]) {
        for url in urls {
            switch CookieCommand.parse(url) {
            case .success(let command):
                perform(command)
            case .failure(let error):
                log.notice("Ignored link \(url.absoluteString, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
    }

    // To-do list
    func showNewTodo() {
        windows.showTextPrompt(title: "New Task", placeholder: "Reply to Sam, water the plants…", actionTitle: "Add") { [weak self] text in
            if self?.desk.addTodo(text) == true { self?.windows.say("Added to your list!", seconds: 3) }
        }
    }

    // Software updates
    func checkForUpdates(userInitiated: Bool = true) {
        UpdateManager.shared.checkForUpdates(userInitiated: userInitiated)
    }

    func showUpdatePrompt() {
        windows.showUpdatePrompt()
    }

    func createCookieMenu() -> NSMenu? {
        if menuBarController == nil {
            menuBarController = MenuBarController(environment: self, store: store)
        }
        return menuBarController?.createMenu()
    }

    func handleAppReopen() {
        if !store.profile.isCompanionVisible {
            windows.showCompanion()
        }
        windows.companionController?.window?.makeKeyAndOrderFront(nil)
        windows.companionController?.showMenu()
    }

    func quit() {
        NSApp.terminate(nil)
    }

    func shutdown() {
        clipboard.stop()
        helpers.stop()
        desk.stop()
        behaviorEngine.stop()
        windows.companionController?.savePosition()
        store.flush()
        menuBarController = nil
    }

    private func presentWelcome() {
        log.info("First run — presenting welcome window")
        windows.showWelcome(
            onContinue: { [weak self] name, personality in
                self?.completeWelcome(name: name, personality: personality)
            },
            onDismissed: { [weak self] in
                self?.handleWelcomeDismissed()
            }
        )
    }
}
