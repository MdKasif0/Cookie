import AppKit
import CoreGraphics
import os

/// Discovers, filters, and models visible application windows on the macOS desktop.
///
/// Uses official Quartz Window Services (`CGWindowListCopyWindowInfo`) without screenshots,
/// private memory scraping, or accessibility permission requirements.
/// Transforms raw display coordinates into AppKit global space and builds navigable edge paths.
@MainActor
final class WindowEnvironmentProvider: ObservableObject {
    // MARK: - Published Properties

    /// Cached list of candidate observable application windows, ordered front-to-back.
    @Published private(set) var candidateWindows: [ObservableWindow] = []

    /// Navigable edge paths extracted from candidate windows.
    @Published private(set) var navigablePaths: [WindowEdgePath] = []

    /// Current navigation graph representing connected window perimeters.
    @Published private(set) var navigationGraph: WindowNavGraph = WindowNavGraph()

    // MARK: - Configuration & Seams for Deterministic Testing

    /// Seam for supplying raw window dictionaries during tests.
    var windowListProvider: () -> [[String: Any]]? = {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        return CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
    }

    /// Seam for supplying primary screen height during coordinate conversions.
    var primaryScreenHeightProvider: () -> CGFloat = {
        DesktopCoordinateSpace.primaryScreenHeight()
    }

    /// Seam for time in tests.
    var now: () -> Date = { Date() }

    /// Minimum window dimensions considered usable for edge exploration.
    var minimumWindowSize = CGSize(width: 160, height: 160)
    var minimumWindowArea: CGFloat = 30000

    private let log = Logger(subsystem: "com.cookie.mac", category: "WindowEnvironment")
    private var lastScanTime = Date.distantPast
    private let scanThrottleInterval: TimeInterval = 0.4

    private var screenParamsObserver: NSObjectProtocol?

    // MARK: - Initialization

    init() {
        refreshWindows(force: true)
        setupNotificationObservers()
    }

    deinit {
        if let screenParamsObserver {
            NotificationCenter.default.removeObserver(screenParamsObserver)
        }
    }

    private func setupNotificationObservers() {
        screenParamsObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshWindows(force: true)
        }
    }

    // MARK: - Window Discovery & Filtering

    /// Refreshes candidate windows and navigable edge paths with throttling protection.
    @discardableResult
    func refreshWindows(force: Bool = false) -> [ObservableWindow] {
        let currentTime = now()
        guard force || currentTime.timeIntervalSince(lastScanTime) >= scanThrottleInterval else {
            return candidateWindows
        }
        lastScanTime = currentTime

        guard let rawList = windowListProvider() else {
            candidateWindows = []
            navigablePaths = []
            navigationGraph = WindowNavGraph()
            return []
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let primaryH = primaryScreenHeightProvider()
        let screens = NSScreen.screens

        var filteredWindows: [ObservableWindow] = []
        var frontWindowRects: [NSRect] = []

        // System processes whose windows are never valid movement surfaces
        let systemOwnersToIgnore: Set<String> = [
            "Window Server", "Dock", "Control Center", "Notification Center",
            "Spotlight", "Wallpaper", "loginwindow", "SystemUIServer", "TextInputMenuAgent"
        ]

        for entry in rawList {
            // 1. Filter out Cookie's own application window(s)
            guard let ownerPID = entry[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID != currentPID else {
                continue
            }

            // 2. Filter out system UI elements by owner name
            let ownerName = entry[kCGWindowOwnerName as String] as? String ?? ""
            guard !systemOwnersToIgnore.contains(ownerName) else {
                continue
            }

            // 3. Filter by window layer (Layer 0 represents standard application windows)
            let layer = entry[kCGWindowLayer as String] as? Int ?? -1
            guard layer == 0 else {
                continue
            }

            // 4. Extract and convert Quartz display bounds to AppKit global coordinates
            guard let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let quartzBounds = CGRect(dictionaryRepresentation: boundsDict) else {
                continue
            }

            let appKitBounds = DesktopCoordinateSpace.quartzRectToAppKit(
                quartzBounds,
                primaryScreenHeight: primaryH
            )

            // 5. Filter out tiny, transient, or invalid dimension windows
            guard appKitBounds.width >= minimumWindowSize.width,
                  appKitBounds.height >= minimumWindowSize.height,
                  (appKitBounds.width * appKitBounds.height) >= minimumWindowArea else {
                continue
            }

            // 6. Ensure window intersects at least one connected display's visible area
            let onAnyScreen = screens.isEmpty || screens.contains(where: { screen in
                screen.visibleFrame.intersects(appKitBounds)
            })
            guard onAnyScreen else {
                continue
            }

            // 7. Calculate occlusion: check if this window is covered by windows in front of it
            let isOccluded = checkOcclusion(windowBounds: appKitBounds, frontWindows: frontWindowRects)

            guard let windowID = entry[kCGWindowNumber as String] as? CGWindowID else {
                continue
            }

            let window = ObservableWindow(
                id: windowID,
                ownerName: ownerName,
                ownerPID: ownerPID,
                layer: layer,
                bounds: appKitBounds,
                isOccluded: isOccluded,
                lastObserved: currentTime
            )

            filteredWindows.append(window)
            frontWindowRects.append(appKitBounds)
        }

        self.candidateWindows = filteredWindows
        rebuildPathsAndGraph(for: filteredWindows)

        log.debug("Discovered \(filteredWindows.count, privacy: .public) candidate windows")
        return filteredWindows
    }

    // MARK: - Occlusion Assessment

    /// Evaluates whether a proposed window is substantially occluded by windows higher in Z-order.
    private func checkOcclusion(windowBounds: NSRect, frontWindows: [NSRect]) -> Bool {
        for front in frontWindows {
            if front.contains(windowBounds) {
                return true
            }
            // If top edge is completely covered by a window in front
            let topEdgeRect = NSRect(
                x: windowBounds.minX + 30,
                y: windowBounds.maxY - 10,
                width: max(1, windowBounds.width - 60),
                height: 20
            )
            if front.contains(topEdgeRect) {
                return true
            }
        }
        return false
    }

    // MARK: - Navigation Path & Graph Construction

    /// Reconstructs navigable edge corridors and navigation graph nodes from active candidate windows.
    private func rebuildPathsAndGraph(for windows: [ObservableWindow]) {
        var paths: [WindowEdgePath] = []
        var graph = WindowNavGraph()

        for window in windows where !window.isOccluded {
            let b = window.bounds
            let cornerInset: CGFloat = 20
            let footOffset: CGFloat = 14 // Calibrated foot offset so Cookie stands right atop the edge

            // 1. Top Horizontal Edge Path
            let topStart = CGPoint(x: b.minX + cornerInset, y: b.maxY + footOffset)
            let topEnd = CGPoint(x: b.maxX - cornerInset, y: b.maxY + footOffset)
            let topPath = WindowEdgePath(
                id: "win-\(window.id)-top",
                windowId: window.id,
                ownerName: window.ownerName,
                edgeType: .topHorizontal,
                startPoint: topStart,
                endPoint: topEnd,
                windowBounds: b,
                footOffset: footOffset
            )
            paths.append(topPath)

            // 2. Left Vertical Edge Path
            let leftStart = CGPoint(x: b.minX - 8, y: b.maxY - cornerInset)
            let leftEnd = CGPoint(x: b.minX - 8, y: b.minY + cornerInset)
            let leftPath = WindowEdgePath(
                id: "win-\(window.id)-left",
                windowId: window.id,
                ownerName: window.ownerName,
                edgeType: .leftVertical,
                startPoint: leftStart,
                endPoint: leftEnd,
                windowBounds: b,
                footOffset: 8
            )
            paths.append(leftPath)

            // 3. Right Vertical Edge Path
            let rightStart = CGPoint(x: b.maxX + 8, y: b.maxY - cornerInset)
            let rightEnd = CGPoint(x: b.maxX + 8, y: b.minY + cornerInset)
            let rightPath = WindowEdgePath(
                id: "win-\(window.id)-right",
                windowId: window.id,
                ownerName: window.ownerName,
                edgeType: .rightVertical,
                startPoint: rightStart,
                endPoint: rightEnd,
                windowBounds: b,
                footOffset: 8
            )
            paths.append(rightPath)

            // 4. Construct Navigation Graph Nodes
            let topLeftNode = WindowNavNode(
                id: "node-\(window.id)-TL",
                point: topStart,
                windowId: window.id,
                isCorner: true,
                cornerEdgeTypes: [.topHorizontal, .leftVertical]
            )
            let topRightNode = WindowNavNode(
                id: "node-\(window.id)-TR",
                point: topEnd,
                windowId: window.id,
                isCorner: true,
                cornerEdgeTypes: [.topHorizontal, .rightVertical]
            )
            let bottomLeftNode = WindowNavNode(
                id: "node-\(window.id)-BL",
                point: leftEnd,
                windowId: window.id,
                isCorner: true,
                cornerEdgeTypes: [.leftVertical, .bottomHorizontal]
            )
            let bottomRightNode = WindowNavNode(
                id: "node-\(window.id)-BR",
                point: rightEnd,
                windowId: window.id,
                isCorner: true,
                cornerEdgeTypes: [.rightVertical, .bottomHorizontal]
            )

            graph.addNode(topLeftNode)
            graph.addNode(topRightNode)
            graph.addNode(bottomLeftNode)
            graph.addNode(bottomRightNode)

            // 5. Connect Navigation Graph Edges
            graph.addEdge(WindowNavEdge(
                id: "edge-\(window.id)-top",
                fromNodeId: topLeftNode.id,
                toNodeId: topRightNode.id,
                edgeType: .topHorizontal,
                path: topPath
            ))
            graph.addEdge(WindowNavEdge(
                id: "edge-\(window.id)-left",
                fromNodeId: topLeftNode.id,
                toNodeId: bottomLeftNode.id,
                edgeType: .leftVertical,
                path: leftPath
            ))
            graph.addEdge(WindowNavEdge(
                id: "edge-\(window.id)-right",
                fromNodeId: topRightNode.id,
                toNodeId: bottomRightNode.id,
                edgeType: .rightVertical,
                path: rightPath
            ))
        }

        self.navigablePaths = paths
        self.navigationGraph = graph
    }

    /// Finds candidate window closest to a given screen point.
    func findClosestCandidate(to point: CGPoint, maxDistance: CGFloat = 650) -> ObservableWindow? {
        var closestWindow: ObservableWindow?
        var minDistance: CGFloat = maxDistance

        for win in candidateWindows where !win.isOccluded {
            // Distance from point to closest point on the window rectangle
            let clampedX = max(win.bounds.minX, min(win.bounds.maxX, point.x))
            let clampedY = max(win.bounds.minY, min(win.bounds.maxY, point.y))
            let dist = hypot(clampedX - point.x, clampedY - point.y)
            if dist < minDistance {
                minDistance = dist
                closestWindow = win
            }
        }

        return closestWindow
    }
}
