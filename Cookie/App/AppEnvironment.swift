import AppKit
import os

/// Composition root: builds the store, audio, behavior engine, and window
/// manager, wires them together, and drives the launch flow.
@MainActor
final class AppEnvironment: ObservableObject {
    let store: CookieStore
    let audioManager: AudioManager
    let behaviorEngine: CookieBehaviorEngine
    let windows: WindowManager

    private let log = Logger(subsystem: "com.cookie.mac", category: "App")

    init() {
        let store = CookieStore()
        let audioManager = AudioManager(store: store)
        let behaviorEngine = CookieBehaviorEngine(store: store)
        self.store = store
        self.audioManager = audioManager
        self.behaviorEngine = behaviorEngine
        self.windows = WindowManager(store: store, audioManager: audioManager, behaviorEngine: behaviorEngine)
    }

    /// Called once at launch. Returning users go straight to the desktop
    /// companion; first-time users meet Cookie in the welcome window.
    func start() {
        store.statistics.recordLaunch()
        if store.profile.hasCompletedWelcome {
            log.info("Returning user — starting companion")
            windows.showCompanion()
            behaviorEngine.start()
        } else {
            presentWelcome()
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

    func quit() {
        NSApp.terminate(nil)
    }

    func shutdown() {
        behaviorEngine.stop()
        store.flush()
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
