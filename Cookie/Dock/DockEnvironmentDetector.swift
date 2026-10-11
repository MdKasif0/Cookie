import AppKit
import Combine
import os

/// Geometry observation of a physical display containing full screen frame and usable visible frame.
struct ScreenGeometry: Equatable {
    let frame: NSRect
    let visibleFrame: NSRect

    init(frame: NSRect, visibleFrame: NSRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }

    init(screen: NSScreen) {
        self.frame = screen.frame
        self.visibleFrame = screen.visibleFrame
    }
}

/// Dedicated detector responsible for observing macOS screen layouts, detecting Dock orientation,
/// geometry, and visibility state across single and multi-display configurations.
///
/// Uses official macOS APIs (`NSScreen.frame`, `NSScreen.visibleFrame`, and `NSApplication.didChangeScreenParametersNotification`)
/// along with supported system preference inspection (`com.apple.dock`) as a clean, non-intrusive fallback.
/// Does NOT inject into Dock.app, scrape private memory, or modify system settings.
@MainActor
final class DockEnvironmentDetector: ObservableObject {
    // MARK: - Published Properties

    /// Current cached desktop environment representation.
    @Published private(set) var currentEnvironment: DesktopEnvironment

    /// Active Dock orientation detected from screen geometry or system preferences.
    @Published private(set) var dockOrientation: DockOrientation = .bottom

    /// Bounding rectangle of the Dock in macOS global screen coordinates.
    @Published private(set) var dockFrame: NSRect = .zero

    /// Whether the Dock is currently autohidden.
    @Published private(set) var isAutohidden: Bool = false

    // MARK: - Configuration & Seams for Deterministic Testing

    /// Seam for providing screen geometries during tests or from live NSScreen instances.
    var screenGeometriesProvider: () -> [ScreenGeometry] = {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return [ScreenGeometry(frame: NSRect(x: 0, y: 0, width: 1440, height: 900),
                                   visibleFrame: NSRect(x: 0, y: 70, width: 1440, height: 805))]
        }
        return screens.map { ScreenGeometry(screen: $0) }
    }

    /// Seam for reading Dock user preferences.
    var dockDefaultsProvider: () -> UserDefaults? = { UserDefaults(suiteName: "com.apple.dock") }

    private var screenObservers: [NSObjectProtocol] = []
    private let log = Logger(subsystem: "com.cookie.mac", category: "DockDetector")

    // MARK: - Initialization & Teardown

    init() {
        self.currentEnvironment = DesktopEnvironment.fallback
        setupNotifications()
        refreshEnvironment()
    }

    deinit {
        for observer in screenObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func teardown() {
        for observer in screenObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        screenObservers.removeAll()
    }

    // MARK: - Notifications

    private func setupNotifications() {
        let center = NotificationCenter.default
        let screenParamsObs = center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleScreenParametersChanged()
            }
        }
        screenObservers.append(screenParamsObs)

        let wakeObs = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleScreenParametersChanged()
            }
        }
        screenObservers.append(wakeObs)
    }

    private func handleScreenParametersChanged() {
        log.info("Display configuration changed — updating Dock environment")
        refreshEnvironment()
    }

    // MARK: - Environment Detection

    /// Refreshes the cached desktop environment for Cookie's current position.
    @discardableResult
    func refreshEnvironment(forPoint point: CGPoint? = nil) -> DesktopEnvironment {
        let env = detectEnvironment(forPoint: point)
        self.currentEnvironment = env
        self.dockOrientation = env.dockOrientation
        self.dockFrame = env.dockFrame
        self.isAutohidden = (env.dockVisibility == .autohidden)
        return env
    }

    /// Evaluates all active screens to locate the Dock, determining its orientation, thickness,
    /// visibility, and reachable safe-walking boundaries.
    func detectEnvironment(forPoint point: CGPoint? = nil) -> DesktopEnvironment {
        let screens = screenGeometriesProvider()
        guard !screens.isEmpty else {
            return DesktopEnvironment.fallback
        }

        // 1. Identify which screen has the physical Dock or hosts the queried position
        var targetScreen: ScreenGeometry?
        var detectedOrientation: DockOrientation = .unknown
        var detectedThickness: CGFloat = 0

        // Inspect screens for physical visibleFrame exclusions (Dock reservations)
        for screen in screens {
            let f = screen.frame
            let vf = screen.visibleFrame

            // Bottom Dock check: visibleFrame.minY > frame.minY
            let bottomDelta = vf.minY - f.minY
            if bottomDelta > 20 { // Exceeds margin, standard Dock is ~50-90pt
                targetScreen = screen
                detectedOrientation = .bottom
                detectedThickness = bottomDelta
                break
            }

            // Left Dock check: visibleFrame.minX > frame.minX
            let leftDelta = vf.minX - f.minX
            if leftDelta > 20 {
                targetScreen = screen
                detectedOrientation = .left
                detectedThickness = leftDelta
                break
            }

            // Right Dock check: visibleFrame.maxX < frame.maxX
            let rightDelta = f.maxX - vf.maxX
            if rightDelta > 20 {
                targetScreen = screen
                detectedOrientation = .right
                detectedThickness = rightDelta
                break
            }
        }

        // 2. If no physical Dock delta was observed, the Dock is autohidden
        let isAutoHidden: Bool
        let defaults = dockDefaultsProvider()
        let prefAutohide = defaults?.bool(forKey: "autohide") ?? false

        if detectedOrientation == .unknown {
            isAutoHidden = true
            // Read orientation preference ("bottom", "left", "right")
            let prefOrientation = defaults?.string(forKey: "orientation")?.lowercased() ?? "bottom"
            switch prefOrientation {
            case "left": detectedOrientation = .left
            case "right": detectedOrientation = .right
            default: detectedOrientation = .bottom
            }

            // Estimated Dock thickness from preferences or standard default (approx 68 pt)
            let tileSize = defaults?.object(forKey: "tilesize") as? CGFloat ?? 48
            detectedThickness = max(40, tileSize + 20)

            // Screen selection: prioritize screen containing queried point or first display
            if let point, let containingScreen = screens.first(where: { $0.frame.contains(point) }) {
                targetScreen = containingScreen
            } else {
                targetScreen = screens[0]
            }
        } else {
            isAutoHidden = prefAutohide
        }

        guard let screen = targetScreen ?? screens.first else {
            return DesktopEnvironment.fallback
        }

        let sFrame = screen.frame
        let vFrame = screen.visibleFrame

        // 3. Compute Dock bounding rectangle
        let dFrame: NSRect
        switch detectedOrientation {
        case .bottom:
            dFrame = NSRect(x: sFrame.minX, y: sFrame.minY, width: sFrame.width, height: detectedThickness)
        case .left:
            dFrame = NSRect(x: sFrame.minX, y: sFrame.minY, width: detectedThickness, height: sFrame.height)
        case .right:
            dFrame = NSRect(x: sFrame.maxX - detectedThickness, y: sFrame.minY, width: detectedThickness, height: sFrame.height)
        case .unknown:
            dFrame = NSRect(x: sFrame.minX, y: sFrame.minY, width: sFrame.width, height: 60)
        }

        // 4. Compute Reachable Safe Walking Surface immediately adjacent to the Dock
        let safeSurface: NSRect
        let safetyMargin: CGFloat = 36 // Inset from screen edges to prevent hitting corners or menu bar
        let walkingDepth: CGFloat = 48  // Depth of the reachable adjacent walking corridor

        switch detectedOrientation {
        case .bottom:
            // Horizontal corridor resting comfortably above the bottom Dock
            let y = vFrame.minY + 6
            let x = vFrame.minX + safetyMargin
            let w = max(100, vFrame.width - (safetyMargin * 2))
            safeSurface = NSRect(x: x, y: y, width: w, height: walkingDepth)

        case .left:
            // Vertical corridor running beside the left-side Dock
            let x = vFrame.minX + 6
            let y = vFrame.minY + safetyMargin
            let h = max(100, vFrame.height - (safetyMargin * 2))
            safeSurface = NSRect(x: x, y: y, width: walkingDepth, height: h)

        case .right:
            // Vertical corridor running beside the right-side Dock
            let x = max(vFrame.minX, vFrame.maxX - walkingDepth - 6)
            let y = vFrame.minY + safetyMargin
            let h = max(100, vFrame.height - (safetyMargin * 2))
            safeSurface = NSRect(x: x, y: y, width: walkingDepth, height: h)

        case .unknown:
            safeSurface = NSRect(x: vFrame.minX + safetyMargin, y: vFrame.minY + 6, width: vFrame.width - (safetyMargin * 2), height: walkingDepth)
        }

        return DesktopEnvironment(
            screenFrame: sFrame,
            visibleFrame: vFrame,
            dockFrame: dFrame,
            dockOrientation: detectedOrientation,
            dockVisibility: isAutoHidden ? .autohidden : .visible,
            safeWalkingSurface: safeSurface,
            dockThickness: detectedThickness
        )
    }
}
