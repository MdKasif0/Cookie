import AppKit
import SwiftUI
import Combine
import os

/// Owns every window Cookie shows: the desktop companion panel and the
/// first-run welcome window. Settings is owned by the SwiftUI `Settings`
/// scene. Closing windows never quits the app — the companion and the
/// menu bar keep it alive.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    private let store: CookieStore
    private let audioManager: AudioManager
    private let behaviorEngine: CookieBehaviorEngine

    private(set) var companionController: CompanionPanelController?
    private(set) var worldItemController: WorldItemPanelController?
    private(set) var welcomeWindow: NSWindow?
    private(set) var customizationWindow: NSWindow?
    private(set) var settingsWindow: NSWindow?
    private(set) var emotePickerWindow: NSWindow?
    weak var environment: AppEnvironment?
    private var onWelcomeDismissed: (() -> Void)?
    private var cancellables: Set<AnyCancellable> = []

    init(store: CookieStore, audioManager: AudioManager, behaviorEngine: CookieBehaviorEngine) {
        self.store = store
        self.audioManager = audioManager
        self.behaviorEngine = behaviorEngine
        super.init()

        let itemController = WorldItemPanelController(behaviorEngine: behaviorEngine)
        self.worldItemController = itemController

        behaviorEngine.$worldItem
            .combineLatest(behaviorEngine.$state)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] item, state in
                guard let self else { return }
                guard self.store.profile.isCompanionVisible else {
                    itemController.hide()
                    return
                }
                let companionFrame = self.companionController?.window?.frame ?? .zero
                itemController.update(
                    item: item,
                    companionFrame: companionFrame,
                    isCookieInBox: state == .inBox
                )
            }
            .store(in: &cancellables)
    }

    var menuProvider: (() -> NSMenu?)?

    // MARK: - Desktop companion

    func showCompanion() {
        if companionController == nil {
            companionController = CompanionPanelController(
                store: store,
                behaviorEngine: behaviorEngine,
                audioManager: audioManager,
                menuProvider: { [weak self] in
                    self?.menuProvider?()
                }
            )
        }
        if store.profile.isCompanionVisible {
            companionController?.show()
            if let item = behaviorEngine.worldItem,
               let frame = companionController?.window?.frame {
                worldItemController?.update(
                    item: item,
                    companionFrame: frame,
                    isCookieInBox: behaviorEngine.state == .inBox
                )
            }
        }
    }

    func toggleCompanion() {
        let shouldShow = !store.profile.isCompanionVisible
        store.profile.isCompanionVisible = shouldShow
        if shouldShow {
            showCompanion()
        } else {
            companionController?.hide()
            worldItemController?.hide()
        }
    }

    // MARK: - First-run welcome

    func showWelcome(
        onContinue: @escaping (String, CookiePersonality) -> Void,
        onDismissed: @escaping () -> Void
    ) {
        onWelcomeDismissed = onDismissed

        if let welcomeWindow {
            welcomeWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Welcome to Cookie"
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        let model = WelcomeViewModel(store: store, onContinue: onContinue)
        let content = WelcomeView(model: model).environmentObject(store)
        panel.contentViewController = NSHostingController(rootView: content)
        panel.center()
        welcomeWindow = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeWelcome() {
        welcomeWindow?.close()
    }

    // MARK: - Customization

    /// The character editor: one window, recreated only when closed.
    func showCustomization() {
        if let customizationWindow {
            customizationWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Customize Cookie"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: CustomizationView().environmentObject(store)
        )
        window.center()
        customizationWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Settings

    func showSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let environment else { return }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 440),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Cookie Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: SettingsView()
                .environmentObject(store)
                .environmentObject(environment)
        )
        window.center()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

/// Specialized borderless floating panel for the emote picker popover.
/// Overrides `canBecomeKey` and `canBecomeMain` so keyboard navigation (1–5, Tab, Return, Esc)
/// works immediately without requiring a titled window decoration.
final class EmotePickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        self.close()
    }
}

extension WindowManager {
    // MARK: - Emotes Panel

    func showEmotePicker() {
        if let emotePickerWindow {
            emotePickerWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let environment else { return }

        let panelWidth: CGFloat = 300
        let panelHeight: CGFloat = 250

        let panel = EmotePickerPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Emotes"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.delegate = self

        let content = EmotePickerView(onDismiss: { [weak self] in
            self?.closeEmotePicker()
        })
        .environmentObject(store)
        .environmentObject(environment)
        .environmentObject(behaviorEngine)

        panel.contentViewController = NSHostingController(rootView: content)

        if let companionWindow = companionController?.window,
           let screen = companionWindow.screen ?? NSScreen.main ?? NSScreen.screens.first {
            let companionFrame = companionWindow.frame
            let visible = screen.visibleFrame

            var x = companionFrame.maxX + 12
            if x + panelWidth > visible.maxX {
                x = companionFrame.minX - panelWidth - 12
            }
            x = max(visible.minX + 8, min(x, visible.maxX - panelWidth - 8))

            var y = companionFrame.midY - panelHeight / 2
            y = max(visible.minY + 8, min(y, visible.maxY - panelHeight - 8))

            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel.center()
        }

        emotePickerWindow = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeEmotePicker() {
        emotePickerWindow?.close()
        emotePickerWindow = nil
    }

    func toggleEmotePicker() {
        if let window = emotePickerWindow, window.isVisible {
            closeEmotePicker()
        } else {
            showEmotePicker()
        }
    }
}

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === welcomeWindow {
            welcomeWindow = nil
            let handler = onWelcomeDismissed
            onWelcomeDismissed = nil
            handler?()
        } else if window === customizationWindow {
            customizationWindow = nil
        } else if window === settingsWindow {
            settingsWindow = nil
        } else if window === emotePickerWindow {
            emotePickerWindow = nil
        }
    }
}
