import XCTest
import AppKit
@testable import Cookie

@MainActor
final class WindowInteractionTests: XCTestCase {

    // MARK: - Helper Mock Factories

    private func makeRawWindowDict(
        id: CGWindowID,
        ownerPID: pid_t,
        ownerName: String,
        layer: Int = 0,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> [String: Any] {
        let rect = CGRect(x: x, y: y, width: width, height: height)
        let boundsDict = rect.dictionaryRepresentation as NSDictionary
        return [
            kCGWindowNumber as String: id,
            kCGWindowOwnerPID as String: ownerPID,
            kCGWindowOwnerName as String: ownerName,
            kCGWindowLayer as String: layer,
            kCGWindowBounds as String: boundsDict
        ]
    }

    // MARK: - 1. Coordinate Conversion Tests

    func testQuartzToAppKitConversionOnPrimaryScreen() {
        let screenHeight: CGFloat = 1080.0
        // Window in Quartz coordinates: top-left at (100, 100), size (800, 600)
        let quartzRect = CGRect(x: 100, y: 100, width: 800, height: 600)
        let appKitRect = DesktopCoordinateSpace.quartzRectToAppKit(quartzRect, primaryScreenHeight: screenHeight)

        // In AppKit (y-up): bottom is at 1080 - (100 + 600) = 380
        XCTAssertEqual(appKitRect.origin.x, 100)
        XCTAssertEqual(appKitRect.origin.y, 380)
        XCTAssertEqual(appKitRect.size.width, 800)
        XCTAssertEqual(appKitRect.size.height, 600)

        // Top of window in AppKit should be 380 + 600 = 980
        XCTAssertEqual(appKitRect.maxY, 980)

        // Round trip back to Quartz
        let roundTripQuartz = DesktopCoordinateSpace.appKitRectToQuartz(appKitRect, primaryScreenHeight: screenHeight)
        XCTAssertEqual(roundTripQuartz.origin.x, quartzRect.origin.x)
        XCTAssertEqual(roundTripQuartz.origin.y, quartzRect.origin.y)
        XCTAssertEqual(roundTripQuartz.size.width, quartzRect.size.width)
        XCTAssertEqual(roundTripQuartz.size.height, quartzRect.size.height)
    }

    func testPointConversionsRoundTrip() {
        let screenHeight: CGFloat = 1200.0
        let quartzPoint = CGPoint(x: 250, y: 150)
        let appKitPoint = DesktopCoordinateSpace.quartzPointToAppKit(quartzPoint, primaryScreenHeight: screenHeight)

        XCTAssertEqual(appKitPoint.x, 250)
        XCTAssertEqual(appKitPoint.y, 1050) // 1200 - 150

        let recoveredQuartz = DesktopCoordinateSpace.appKitPointToQuartz(appKitPoint, primaryScreenHeight: screenHeight)
        XCTAssertEqual(recoveredQuartz.x, quartzPoint.x)
        XCTAssertEqual(recoveredQuartz.y, quartzPoint.y)
    }

    func testMultiDisplayWithNegativeOrigin() {
        let screenHeight: CGFloat = 1080.0
        // External monitor to the left has negative X in Quartz: (-1920, 200, 1000, 700)
        let quartzRect = CGRect(x: -1920, y: 200, width: 1000, height: 700)
        let appKitRect = DesktopCoordinateSpace.quartzRectToAppKit(quartzRect, primaryScreenHeight: screenHeight)

        XCTAssertEqual(appKitRect.origin.x, -1920)
        XCTAssertEqual(appKitRect.origin.y, 1080 - 900) // 180
        XCTAssertEqual(appKitRect.width, 1000)
        XCTAssertEqual(appKitRect.height, 700)
    }

    func testScreenToSceneConversions() {
        let companionFrame = NSRect(x: 500, y: 300, width: 160, height: 160)
        let sceneSize = CGSize(width: 160, height: 160)

        // Screen center of companion window (midX: 580, midY: 380)
        let centerPoint = NSPoint(x: 580, y: 380)
        let scenePoint = DesktopCoordinateSpace.screenPointToScene(centerPoint, windowFrame: companionFrame, sceneSize: sceneSize)
        XCTAssertEqual(scenePoint.x, 0)
        XCTAssertEqual(scenePoint.y, 0)

        // Point offset by (20, 40)
        let offsetPoint = NSPoint(x: 600, y: 420)
        let offsetScene = DesktopCoordinateSpace.screenPointToScene(offsetPoint, windowFrame: companionFrame, sceneSize: sceneSize)
        XCTAssertEqual(offsetScene.x, 20)
        XCTAssertEqual(offsetScene.y, 40)

        // Recovered screen point
        let recoveredScreen = DesktopCoordinateSpace.scenePointToScreen(offsetScene, windowFrame: companionFrame)
        XCTAssertEqual(recoveredScreen.x, offsetPoint.x)
        XCTAssertEqual(recoveredScreen.y, offsetPoint.y)
    }

    // MARK: - 2. Window Discovery and Filtering

    func testWindowFilteringIgnoresOwnProcess() {
        let provider = WindowEnvironmentProvider()
        let ownPID = ProcessInfo.processInfo.processIdentifier

        provider.primaryScreenHeightProvider = { 1080.0 }
        provider.windowListProvider = {
            [
                // Cookie's own window
                self.makeRawWindowDict(id: 101, ownerPID: ownPID, ownerName: "Cookie", layer: 0, x: 200, y: 200, width: 500, height: 400),
                // External application window (Safari)
                self.makeRawWindowDict(id: 102, ownerPID: 9999, ownerName: "Safari", layer: 0, x: 300, y: 150, width: 800, height: 600)
            ]
        }

        let windows = provider.refreshWindows(force: true)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows.first?.id, 102)
        XCTAssertEqual(windows.first?.ownerName, "Safari")
    }

    func testWindowFilteringIgnoresSystemChromeAndNonZeroLayers() {
        let provider = WindowEnvironmentProvider()
        provider.primaryScreenHeightProvider = { 1080.0 }
        provider.windowListProvider = {
            [
                // Dock (system chrome)
                self.makeRawWindowDict(id: 201, ownerPID: 501, ownerName: "Dock", layer: 0, x: 0, y: 1000, width: 1920, height: 80),
                // Control Center
                self.makeRawWindowDict(id: 202, ownerPID: 502, ownerName: "Control Center", layer: 0, x: 1700, y: 0, width: 220, height: 300),
                // Non-zero layer (e.g. desktop background layer -1)
                self.makeRawWindowDict(id: 203, ownerPID: 503, ownerName: "Wallpaper", layer: -1, x: 0, y: 0, width: 1920, height: 1080),
                // Valid application window (Notes)
                self.makeRawWindowDict(id: 204, ownerPID: 8888, ownerName: "Notes", layer: 0, x: 100, y: 100, width: 600, height: 500)
            ]
        }

        let windows = provider.refreshWindows(force: true)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows.first?.id, 204)
        XCTAssertEqual(windows.first?.ownerName, "Notes")
    }

    func testWindowFilteringIgnoresTinyOrTransientWindows() {
        let provider = WindowEnvironmentProvider()
        provider.primaryScreenHeightProvider = { 1080.0 }
        provider.windowListProvider = {
            [
                // Tiny tooltip (width 120 < 160)
                self.makeRawWindowDict(id: 301, ownerPID: 7777, ownerName: "Xcode", layer: 0, x: 50, y: 50, width: 120, height: 40),
                // Small popup (area < 30000)
                self.makeRawWindowDict(id: 302, ownerPID: 7777, ownerName: "Xcode", layer: 0, x: 50, y: 50, width: 170, height: 140),
                // Standard main window
                self.makeRawWindowDict(id: 303, ownerPID: 7777, ownerName: "Xcode", layer: 0, x: 100, y: 100, width: 900, height: 700)
            ]
        }

        let windows = provider.refreshWindows(force: true)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows.first?.id, 303)
    }

    // MARK: - 3. Occlusion Assessment

    func testOcclusionAssessmentDetectsCoveredWindows() {
        let provider = WindowEnvironmentProvider()
        provider.primaryScreenHeightProvider = { 1080.0 }
        provider.windowListProvider = {
            [
                // Front window (Z-order 0): covers x: 200...1000, y in Quartz: 100...700
                self.makeRawWindowDict(id: 401, ownerPID: 6001, ownerName: "Safari", layer: 0, x: 200, y: 100, width: 800, height: 600),
                // Back window (Z-order 1): completely underneath Safari
                self.makeRawWindowDict(id: 402, ownerPID: 6002, ownerName: "TextEdit", layer: 0, x: 250, y: 150, width: 500, height: 400),
                // Partially exposed window on the right
                self.makeRawWindowDict(id: 403, ownerPID: 6003, ownerName: "Calendar", layer: 0, x: 1100, y: 100, width: 600, height: 500)
            ]
        }

        let windows = provider.refreshWindows(force: true)
        XCTAssertEqual(windows.count, 3)

        let safari = windows.first(where: { $0.id == 401 })!
        let textEdit = windows.first(where: { $0.id == 402 })!
        let calendar = windows.first(where: { $0.id == 403 })!

        XCTAssertFalse(safari.isOccluded)
        XCTAssertTrue(textEdit.isOccluded)
        XCTAssertFalse(calendar.isOccluded)

        // Traversable paths should only be generated for unoccluded windows
        let pathsForTextEdit = provider.navigablePaths.filter { $0.windowId == 402 }
        XCTAssertTrue(pathsForTextEdit.isEmpty)
        let pathsForSafari = provider.navigablePaths.filter { $0.windowId == 401 }
        XCTAssertFalse(pathsForSafari.isEmpty)
    }

    // MARK: - 4. Movement Surface Model and Edge Paths

    func testNavigableEdgePathsGeometryAndOffsets() {
        let provider = WindowEnvironmentProvider()
        provider.primaryScreenHeightProvider = { 1080.0 }
        provider.windowListProvider = {
            [
                // Window at Quartz (200, 100, 800, 600).
                // AppKit bounds: origin (200, 1080 - 700 = 380), size (800, 600).
                // Top edge maxY = 380 + 600 = 980.
                self.makeRawWindowDict(id: 501, ownerPID: 5001, ownerName: "Finder", layer: 0, x: 200, y: 100, width: 800, height: 600)
            ]
        }

        provider.refreshWindows(force: true)
        let paths = provider.navigablePaths.filter { $0.windowId == 501 }

        let topPath = paths.first(where: { $0.edgeType == .topHorizontal })
        XCTAssertNotNil(topPath)
        guard let top = topPath else { return }

        // Top edge Y has calibrated foot offset (980 + 14 = 994)
        XCTAssertEqual(top.startPoint.y, 994)
        XCTAssertEqual(top.endPoint.y, 994)
        XCTAssertEqual(top.startPoint.x, 220) // minX + cornerInset (200 + 20)
        XCTAssertEqual(top.endPoint.x, 980)   // maxX - cornerInset (1000 - 20)
        XCTAssertEqual(top.length, 760)

        // Midpoint check
        let mid = top.pointAt(progress: 0.5)
        XCTAssertEqual(mid.x, 600)
        XCTAssertEqual(mid.y, 994)

        // Closest point projection check
        let query = CGPoint(x: 400, y: 1050)
        let (projPoint, progress) = top.closestPoint(to: query)
        XCTAssertEqual(projPoint.x, 400, accuracy: 0.1)
        XCTAssertEqual(projPoint.y, 994, accuracy: 0.1)
        XCTAssertEqual(progress, (400 - 220) / 760, accuracy: 0.01)

        // Left vertical edge check
        let leftPath = paths.first(where: { $0.edgeType == .leftVertical })
        XCTAssertNotNil(leftPath)
        guard let left = leftPath else { return }
        XCTAssertEqual(left.startPoint.x, 192) // 200 - 8 offset
        XCTAssertEqual(left.startPoint.y, 960) // maxY - cornerInset (980 - 20)
        XCTAssertEqual(left.endPoint.y, 400)   // minY + cornerInset (380 + 20)

        // Right vertical edge check
        let rightPath = paths.first(where: { $0.edgeType == .rightVertical })
        XCTAssertNotNil(rightPath)
        guard let right = rightPath else { return }
        XCTAssertEqual(right.startPoint.x, 1008) // 1000 + 8 offset
        XCTAssertEqual(right.startPoint.y, 960)
        XCTAssertEqual(right.endPoint.y, 400)
    }

    // MARK: - 5. Navigation Graph Construction

    func testNavigationGraphStructure() {
        let provider = WindowEnvironmentProvider()
        provider.primaryScreenHeightProvider = { 1080.0 }
        provider.windowListProvider = {
            [
                self.makeRawWindowDict(id: 601, ownerPID: 6001, ownerName: "Preview", layer: 0, x: 300, y: 200, width: 700, height: 500)
            ]
        }

        provider.refreshWindows(force: true)
        let graph = provider.navigationGraph

        let tlNode = graph.node(for: "node-601-TL")
        let trNode = graph.node(for: "node-601-TR")
        let blNode = graph.node(for: "node-601-BL")
        let brNode = graph.node(for: "node-601-BR")

        XCTAssertNotNil(tlNode)
        XCTAssertNotNil(trNode)
        XCTAssertNotNil(blNode)
        XCTAssertNotNil(brNode)
        XCTAssertTrue(tlNode?.isCorner ?? false)

        // Outgoing edges from top-left corner
        let tlEdges = graph.outgoingEdges(from: "node-601-TL")
        XCTAssertEqual(tlEdges.count, 2)
        XCTAssertTrue(tlEdges.contains(where: { $0.edgeType == .topHorizontal && $0.toNodeId == "node-601-TR" }))
        XCTAssertTrue(tlEdges.contains(where: { $0.edgeType == .leftVertical && $0.toNodeId == "node-601-BL" }))

        // Outgoing edge from top-right corner to bottom-right
        let trEdges = graph.outgoingEdges(from: "node-601-TR")
        XCTAssertTrue(trEdges.contains(where: { $0.edgeType == .rightVertical && $0.toNodeId == "node-601-BR" }))
    }

    // MARK: - 6. Exploration State Progression

    func testWindowExplorationStateProgression() {
        let provider = WindowEnvironmentProvider()
        provider.primaryScreenHeightProvider = { 1080.0 }
        provider.windowListProvider = {
            [
                self.makeRawWindowDict(id: 701, ownerPID: 7001, ownerName: "Safari", layer: 0, x: 200, y: 100, width: 800, height: 600)
            ]
        }
        var simulatedTime = Date()
        provider.now = { simulatedTime }
        provider.refreshWindows(force: true)

        let controller = WindowInteractionController(provider: provider)
        controller.now = { simulatedTime }

        // Start Cookie near top edge (top edge is at y = 994, x: 220...980)
        let cookiePos = NSPoint(x: 250, y: 994)
        controller.startExploration(fromPosition: cookiePos, frequency: .frequent)

        XCTAssertTrue(controller.isExploringWindow)
        XCTAssertEqual(controller.currentPhase, .anticipating)
        XCTAssertNotNil(controller.destinationPoint)
        XCTAssertNotNil(controller.windowLookAngle) // Gazing toward target

        // Tick past anticipation duration (~0.7s)
        simulatedTime = simulatedTime.addingTimeInterval(0.7)
        controller.tick(dt: 0.7, cookiePosition: cookiePos, characterSize: CGSize(width: 80, height: 80), frequency: .frequent, verticalClimbingEnabled: false)
        XCTAssertEqual(controller.currentPhase, .approaching)

        // Move Cookie to destination point
        let arrivalPos = controller.destinationPoint!
        simulatedTime = simulatedTime.addingTimeInterval(0.1)
        controller.tick(dt: 0.1, cookiePosition: arrivalPos, characterSize: CGSize(width: 80, height: 80), frequency: .frequent, verticalClimbingEnabled: false)
        XCTAssertEqual(controller.currentPhase, .walkingTopEdge)

        // Advance walk across top edge
        let initialProgress = controller.edgeProgress
        simulatedTime = simulatedTime.addingTimeInterval(2.0)
        controller.tick(dt: 2.0, cookiePosition: arrivalPos, characterSize: CGSize(width: 80, height: 80), frequency: .frequent, verticalClimbingEnabled: false)
        XCTAssertGreaterThan(controller.edgeProgress, initialProgress)

        // Walk to corner
        simulatedTime = simulatedTime.addingTimeInterval(5.0)
        controller.tick(dt: 5.0, cookiePosition: arrivalPos, characterSize: CGSize(width: 80, height: 80), frequency: .frequent, verticalClimbingEnabled: false)
        XCTAssertEqual(controller.currentPhase, .cornerTransition)
    }

    func testVerticalClimbingWhenEnabled() {
        let provider = WindowEnvironmentProvider()
        provider.primaryScreenHeightProvider = { 1080.0 }
        provider.windowListProvider = {
            [
                self.makeRawWindowDict(id: 801, ownerPID: 8001, ownerName: "Safari", layer: 0, x: 200, y: 100, width: 800, height: 600)
            ]
        }
        var simulatedTime = Date()
        provider.now = { simulatedTime }
        provider.refreshWindows(force: true)

        let controller = WindowInteractionController(provider: provider)
        controller.now = { simulatedTime }

        // Start Cookie near top-left access point (220, 994)
        controller.startExploration(fromPosition: NSPoint(x: 250, y: 994), frequency: .frequent)

        // 1. Anticipating -> approaching
        simulatedTime = simulatedTime.addingTimeInterval(0.7)
        controller.tick(dt: 0.7, cookiePosition: NSPoint(x: 250, y: 994), characterSize: CGSize(width: 80, height: 80), frequency: .frequent, verticalClimbingEnabled: true)
        XCTAssertEqual(controller.currentPhase, .approaching)

        // 2. Approaching -> walkingTopEdge
        simulatedTime = simulatedTime.addingTimeInterval(0.1)
        controller.tick(dt: 0.1, cookiePosition: controller.destinationPoint!, characterSize: CGSize(width: 80, height: 80), frequency: .frequent, verticalClimbingEnabled: true)
        XCTAssertEqual(controller.currentPhase, .walkingTopEdge)

        // 3. Walk to the right corner (edgeProgress -> 1.0)
        simulatedTime = simulatedTime.addingTimeInterval(7.0)
        controller.tick(dt: 7.0, cookiePosition: controller.destinationPoint!, characterSize: CGSize(width: 80, height: 80), frequency: .frequent, verticalClimbingEnabled: true)
        XCTAssertEqual(controller.currentPhase, .cornerTransition)
        XCTAssertGreaterThanOrEqual(controller.edgeProgress, 0.9)

        // 4. Corner transition with vertical climbing enabled -> transitions to climbingVerticalEdge
        simulatedTime = simulatedTime.addingTimeInterval(1.6)
        controller.tick(dt: 1.6, cookiePosition: controller.destinationPoint!, characterSize: CGSize(width: 80, height: 80), frequency: .frequent, verticalClimbingEnabled: true)
        XCTAssertEqual(controller.currentPhase, .climbingVerticalEdge)
        XCTAssertEqual(controller.activeEdgePath?.edgeType, .rightVertical)
    }

    // MARK: - 7. Window Movement and Resizing Reconciliation

    func testWindowMovementReconciliation() {
        let provider = WindowEnvironmentProvider()
        provider.primaryScreenHeightProvider = { 1080.0 }

        var currentWindowY: CGFloat = 100
        provider.windowListProvider = {
            [
                self.makeRawWindowDict(id: 901, ownerPID: 9001, ownerName: "Safari", layer: 0, x: 200, y: currentWindowY, width: 800, height: 600)
            ]
        }
        var simulatedTime = Date()
        provider.now = { simulatedTime }
        provider.refreshWindows(force: true)

        let controller = WindowInteractionController(provider: provider)
        controller.now = { simulatedTime }

        controller.startExploration(fromPosition: NSPoint(x: 250, y: 994), frequency: .frequent)

        // Anticipate -> approaching
        simulatedTime = simulatedTime.addingTimeInterval(0.7)
        controller.tick(dt: 0.7, cookiePosition: NSPoint(x: 250, y: 994), characterSize: CGSize(width: 80, height: 80), frequency: .frequent, verticalClimbingEnabled: false)

        // Arrive -> walkingTopEdge
        simulatedTime = simulatedTime.addingTimeInterval(0.1)
        controller.tick(dt: 0.1, cookiePosition: controller.destinationPoint!, characterSize: CGSize(width: 80, height: 80), frequency: .frequent, verticalClimbingEnabled: false)
        XCTAssertEqual(controller.currentPhase, .walkingTopEdge)

        let originalDestY = controller.destinationPoint!.y

        // User dragged the Safari window downwards in Quartz (y: 100 -> 250)
        currentWindowY = 250
        simulatedTime = simulatedTime.addingTimeInterval(0.6) // Trigger reconciliation (> 0.5s)
        controller.tick(dt: 0.1, cookiePosition: controller.destinationPoint!, characterSize: CGSize(width: 80, height: 80), frequency: .frequent, verticalClimbingEnabled: false)

        let updatedDestY = controller.destinationPoint!.y
        // Window moved down in Quartz, so its AppKit Y moved down (1080 - (250+600) = 230 vs original 380)
        XCTAssertNotEqual(originalDestY, updatedDestY)
        XCTAssertEqual(controller.activeWindow?.id, 901)
    }

    func testWindowClosingTriggersSafeDismount() {
        let provider = WindowEnvironmentProvider()
        provider.primaryScreenHeightProvider = { 1080.0 }

        var windowPresent = true
        provider.windowListProvider = {
            if windowPresent {
                return [self.makeRawWindowDict(id: 902, ownerPID: 9002, ownerName: "Safari", layer: 0, x: 200, y: 100, width: 800, height: 600)]
            } else {
                return []
            }
        }
        var simulatedTime = Date()
        provider.now = { simulatedTime }
        provider.refreshWindows(force: true)

        let controller = WindowInteractionController(provider: provider)
        controller.now = { simulatedTime }

        controller.startExploration(fromPosition: NSPoint(x: 250, y: 994), frequency: .frequent)

        // Anticipating -> approaching
        simulatedTime = simulatedTime.addingTimeInterval(0.7)
        controller.tick(dt: 0.7, cookiePosition: NSPoint(x: 250, y: 994), characterSize: CGSize(width: 80, height: 80), frequency: .frequent, verticalClimbingEnabled: false)

        // Approaching -> walkingTopEdge
        simulatedTime = simulatedTime.addingTimeInterval(0.1)
        controller.tick(dt: 0.1, cookiePosition: controller.destinationPoint!, characterSize: CGSize(width: 80, height: 80), frequency: .frequent, verticalClimbingEnabled: false)
        XCTAssertEqual(controller.currentPhase, .walkingTopEdge)

        // Window closes!
        windowPresent = false
        simulatedTime = simulatedTime.addingTimeInterval(0.6)
        controller.tick(dt: 0.1, cookiePosition: controller.destinationPoint!, characterSize: CGSize(width: 80, height: 80), frequency: .frequent, verticalClimbingEnabled: false)

        // Should gracefully transition to departing toward ground rather than crash or hang
        XCTAssertEqual(controller.currentPhase, .departing)
    }

    // MARK: - 8. Behavior Engine Priority and Interruption

    func testDraggingInterruptsWindowExploration() {
        let store = CookieStore()
        store.profile.settings.windowInteraction = true

        let provider = WindowEnvironmentProvider()
        provider.primaryScreenHeightProvider = { 1080.0 }
        provider.windowListProvider = {
            [self.makeRawWindowDict(id: 1001, ownerPID: 1001, ownerName: "Finder", layer: 0, x: 200, y: 100, width: 800, height: 600)]
        }
        var simulatedTime = Date()
        provider.now = { simulatedTime }
        provider.refreshWindows(force: true)

        let controller = WindowInteractionController(provider: provider)
        controller.now = { simulatedTime }
        let engine = CookieBehaviorEngine(
            store: store,
            windowProvider: provider,
            windowController: controller
        )
        engine.now = { simulatedTime }
        engine.start()

        controller.startExploration(fromPosition: NSPoint(x: 250, y: 994), frequency: .frequent)
        XCTAssertTrue(controller.isExploringWindow)

        // User grabs Cookie
        engine.handleGrab()
        XCTAssertEqual(engine.state, .beingDragged)
        XCTAssertFalse(controller.isExploringWindow)
        XCTAssertEqual(controller.currentPhase, .idle)
    }

    func testEmoteInterruptsWindowExploration() {
        let store = CookieStore()
        let provider = WindowEnvironmentProvider()
        provider.primaryScreenHeightProvider = { 1080.0 }
        provider.windowListProvider = {
            [self.makeRawWindowDict(id: 1002, ownerPID: 1002, ownerName: "Finder", layer: 0, x: 200, y: 100, width: 800, height: 600)]
        }
        var simulatedTime = Date()
        provider.now = { simulatedTime }
        provider.refreshWindows(force: true)

        let controller = WindowInteractionController(provider: provider)
        controller.now = { simulatedTime }
        let engine = CookieBehaviorEngine(
            store: store,
            windowProvider: provider,
            windowController: controller
        )
        engine.now = { simulatedTime }
        engine.start()

        controller.startExploration(fromPosition: NSPoint(x: 250, y: 994), frequency: .frequent)
        XCTAssertTrue(controller.isExploringWindow)

        // Trigger user emote
        let waveEmote = Emote.find(.wave)
        let success = engine.triggerEmote(waveEmote)
        XCTAssertTrue(success)
        XCTAssertEqual(engine.state, .emoting)
        XCTAssertFalse(controller.isExploringWindow)
    }

    func testFeedingInterruptsWindowExploration() {
        let store = CookieStore()
        let provider = WindowEnvironmentProvider()
        provider.primaryScreenHeightProvider = { 1080.0 }
        provider.windowListProvider = {
            [self.makeRawWindowDict(id: 1003, ownerPID: 1003, ownerName: "Finder", layer: 0, x: 200, y: 100, width: 800, height: 600)]
        }
        var simulatedTime = Date()
        provider.now = { simulatedTime }
        provider.refreshWindows(force: true)

        let controller = WindowInteractionController(provider: provider)
        controller.now = { simulatedTime }
        let engine = CookieBehaviorEngine(
            store: store,
            windowProvider: provider,
            windowController: controller
        )
        engine.now = { simulatedTime }
        engine.start()

        controller.startExploration(fromPosition: NSPoint(x: 250, y: 994), frequency: .frequent)
        XCTAssertTrue(controller.isExploringWindow)

        engine.handleFeed(food: .fish)
        XCTAssertFalse(controller.isExploringWindow)
        XCTAssertNotNil(engine.worldItem)
    }

    // MARK: - 9. Settings and Defaults

    func testWindowExplorationSettingsDefaultsAndReset() {
        var settings = CookieSettings()
        XCTAssertTrue(settings.windowInteraction)
        XCTAssertFalse(settings.windowVerticalClimbing)
        XCTAssertEqual(settings.windowExplorationFrequency, "occasional")
        XCTAssertEqual(settings.windowFrequency, .occasional)

        // Change values
        settings.windowInteraction = false
        settings.windowVerticalClimbing = true
        settings.windowExplorationFrequency = "frequent"
        XCTAssertEqual(settings.windowFrequency, .frequent)

        // Reset window settings
        settings.resetWindowSettings()
        XCTAssertTrue(settings.windowInteraction)
        XCTAssertFalse(settings.windowVerticalClimbing)
        XCTAssertEqual(settings.windowExplorationFrequency, "occasional")
    }
}
