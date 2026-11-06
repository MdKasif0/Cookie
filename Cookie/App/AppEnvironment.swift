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
    let summonHotKey = SummonHotKey()
    private(set) var menuBarController: MenuBarController?
    private var bondWatch: AnyCancellable?

    private let log = Logger(subsystem: "com.cookie.mac", category: "App")
    private var cancellables: Set<AnyCancellable> = []

    init() {
        let store = CookieStore()
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
        self.quietMode = QuietModeMonitor(store: store)
        windows.environment = self
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
