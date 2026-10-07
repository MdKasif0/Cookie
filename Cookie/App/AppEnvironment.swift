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
    private(set) var menuBarController: MenuBarController?

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
    }

    /// Called once at launch. Returning users go straight to the desktop
    /// companion; first-time users meet Cookie in the welcome window.
    func start() {
        if menuBarController == nil {
            menuBarController = MenuBarController(environment: self, store: store)
        }
        store.statistics.recordLaunch()
        applySystemSettings()
        if store.profile.hasCompletedWelcome {
            log.info("Returning user — starting companion")
            if store.profile.settings.showOnStartup {
                windows.showCompanion()
            }
            behaviorEngine.start()
        } else {
            presentWelcome()
        }
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
        audioManager.play(.welcome)
    }

    /// The welcome window was closed without continuing: start Cookie with
    /// the current (default) settings so the app is still usable.
    private func handleWelcomeDismissed() {
        guard !store.profile.hasCompletedWelcome else { return }
        store.profile.hasCompletedWelcome = true
        windows.showCompanion()
        behaviorEngine.start()
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

    // Menu bar companion commands.
    func petCookie() { behaviorEngine.handleMenuPet() }
    func feedCookie(food: FoodKind? = nil) { behaviorEngine.handleFeed(food: food) }
    func offerToy(_ toy: ToyKind) { behaviorEngine.handleOfferToy(toy) }
    func playWithCookie() { behaviorEngine.handlePlayCommand() }
    func clearWorldItem() { behaviorEngine.clearWorldItem() }
    var hasActiveWorldItem: Bool { behaviorEngine.worldItem != nil }
    func triggerSpecialEvent(_ event: SpecialEventKind) { behaviorEngine.triggerSpecialEvent(event) }

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
