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
    private(set) var updatePromptWindow: NSWindow?
    weak var environment: AppEnvironment?
    let bubbleController = BubblePanelController()
    let cozyController = CozyPanelController()
    /// True while a full-screen app has her stepping aside.
    private(set) var isQuiet = false
    private var sharingHidden = false
    private var companionMoveObserver: NSObjectProtocol?
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
                guard self.store.profile.isCompanionVisible, !self.isQuiet else {
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

        cozyController.onMove = { [weak self] kind, position in self?.moveCozy(kind, to: position) }
        cozyController.onRemove = { [weak self] kind in self?.removeCozy(kind) }

        struct CozyKey: Equatable {
            var items: [CozyPlacement]
            var size: Double
        }
        store.$profile
            .map { CozyKey(items: $0.cozyItems, size: $0.settings.cookieSize) }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshCozy() }
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
        companionController?.window?.sharingType = sharingHidden ? .none : .readOnly
        if companionMoveObserver == nil, let window = companionController?.window {
            companionMoveObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateCozyTargets() }
            }
        }
        if store.profile.isCompanionVisible, !isQuiet {
            companionController?.show()
            refreshCozy()
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
            bubbleController.hide()
            refreshCozy()
        }
    }

    // MARK: - Speech bubbles

    /// Cookie says something, if she is on screen.
    func say(_ text: String, seconds: TimeInterval = 4.5) {
        guard store.profile.isCompanionVisible, !isQuiet else { return }
        bubbleController.say(text, above: companionController?.window, seconds: seconds)
    }

    // MARK: - Quiet mode and screen sharing

    /// Hides everything of hers while a full-screen app is up, and brings her back after.
    func setQuiet(_ quiet: Bool) {
        guard quiet != isQuiet else { return }
        isQuiet = quiet
        bubbleController.isSuppressed = quiet
        if quiet {
            companionController?.hide()
            worldItemController?.hide()
            cozyController.hideAll()
        } else if store.profile.isCompanionVisible {
            showCompanion()
        }
        updateCozyTargets()
    }

    /// Asks the system to leave her out of screen sharing and recordings. How far that holds depends
    /// on the capture method: it is honored by most, but newer macOS capture APIs may ignore it.
    func setSharingHidden(_ hidden: Bool) {
        sharingHidden = hidden
        let type: NSWindow.SharingType = hidden ? .none : .readOnly
        companionController?.window?.sharingType = type
        worldItemController?.window?.sharingType = type
        bubbleController.window.sharingType = type
        cozyController.setSharing(hidden: hidden)
    }

    // MARK: - Summoning

    /// Where she appears when called: beside the cursor, kept on that screen.
    static func summonOrigin(mouse: CGPoint, size: CGSize, visible: CGRect) -> CGPoint {
        var x = mouse.x + 40
        if x + size.width > visible.maxX - 8 { x = mouse.x - 40 - size.width }
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        let y = min(max(mouse.y - size.height / 2, visible.minY + 8), visible.maxY - size.height - 8)
        return CGPoint(x: x, y: y)
    }

    func moveCompanionNearCursor() {
        guard let window = companionController?.window else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        window.setFrameOrigin(Self.summonOrigin(mouse: mouse, size: window.frame.size, visible: visible))
        companionController?.savePosition()
    }

    // MARK: - Cozy items

    /// Where a new cozy item goes: near `preferredX`, clear of the ones already there.
    static func newCozyPosition(preferredX: CGFloat, primaryFrame: CGRect, existing: [CozyPlacement]) -> Double {
        let preferred = CozyPanelController.position(forCenterX: preferredX, primaryFrame: primaryFrame)
        let minimumGap = 0.11
        for step in 0...12 {
            let offsets = step == 0 ? [0.0] : [Double(step) * 0.06, -Double(step) * 0.06]
            for offset in offsets {
                let candidate = preferred + offset
                guard (0.05...0.95).contains(candidate) else { continue }
                if existing.allSatisfy({ abs($0.position - candidate) >= minimumGap }) { return candidate }
            }
        }
        return min(max(preferred, 0.05), 0.95)
    }

    @discardableResult
    func placeCozy(_ kind: CozyKind) -> Bool {
        guard store.isUnlocked(.cozy(kind)), !store.profile.cozyItems.contains(where: { $0.kind == kind }),
              let primary = NSScreen.screens.first else { return false }
        let cookieX = companionController?.window?.frame.midX ?? primary.frame.midX
        let direction: CGFloat = behaviorEngine.facing == .right ? 1 : -1
        let position = Self.newCozyPosition(
            preferredX: cookieX + direction * 190,
            primaryFrame: primary.frame,
            existing: store.profile.cozyItems
        )
        store.profile.cozyItems.append(CozyPlacement(kind: kind, position: position))
        return true
    }

    func removeCozy(_ kind: CozyKind) {
        store.profile.cozyItems.removeAll { $0.kind == kind }
    }

    func moveCozy(_ kind: CozyKind, to position: Double) {
        guard let index = store.profile.cozyItems.firstIndex(where: { $0.kind == kind }) else { return }
        store.profile.cozyItems[index] = CozyPlacement(kind: kind, position: position)
    }

    func refreshCozy() {
        guard store.profile.isCompanionVisible, !isQuiet else {
            cozyController.hideAll()
            updateCozyTargets()
            return
        }
        cozyController.update(
            placements: store.profile.cozyItems,
            companion: companionController?.window,
            scale: CGFloat(store.profile.settings.cookieSize)
        )
        updateCozyTargets()
    }

    /// She can only visit when she is on the floor of the main screen, where the items are.
    private func updateCozyTargets() {
        guard !isQuiet, let primary = NSScreen.screens.first, let frame = companionController?.window?.frame,
              primary.frame.contains(CGPoint(x: frame.midX, y: frame.midY)),
              frame.minY <= CozyPanelController.floorY(primaryVisible: primary.visibleFrame) + 40 else {
            if !behaviorEngine.cozyTargets.isEmpty { behaviorEngine.cozyTargets = [] }
            return
        }
        behaviorEngine.cozyTargets = store.profile.cozyItems.map {
            (kind: $0.kind, x: CozyPanelController.centerX(for: $0, primaryFrame: primary.frame))
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
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Welcome to Cookie"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        let model = WelcomeViewModel(store: store, audioManager: audioManager, onContinue: onContinue)
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

    // MARK: - Photo mode

    private(set) var photoModeWindow: NSWindow?

    func showPhotoMode() {
        if let photoModeWindow {
            if let model = photoModeModel { model.reload() }
            photoModeWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let model = PhotoModeModel(store: store)
        photoModeModel = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Photo Mode"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: PhotoModeView(model: model))
        window.center()
        photoModeWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var photoModeModel: PhotoModeModel?

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

    // MARK: - Emotes Panel

    func showEmotePicker() {
        if let emotePickerWindow {
            emotePickerWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let environment else { return }

        let panelWidth: CGFloat = 300
        let panelHeight: CGFloat = 265

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

    // MARK: - Software Updates Window

    func showUpdatePrompt() {
        if let updatePromptWindow {
            updatePromptWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 280),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "A little update for Cookie"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.delegate = self

        let content = UpdatePromptView(
            updateManager: UpdateManager.shared,
            onDismiss: { [weak self] in
                self?.closeUpdatePrompt()
            }
        )
        panel.contentViewController = NSHostingController(rootView: content)
        panel.center()
        updatePromptWindow = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeUpdatePrompt() {
        updatePromptWindow?.close()
        updatePromptWindow = nil
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
        } else if window === updatePromptWindow {
            updatePromptWindow = nil
        } else if window === photoModeWindow {
            photoModeWindow = nil
            photoModeModel = nil
        }
    }
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

