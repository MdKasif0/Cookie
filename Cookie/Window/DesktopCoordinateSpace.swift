import AppKit
import CoreGraphics

/// Centralized, tested coordinate conversion layer reconciling differences between:
/// 1. Quartz global display coordinates (origin at top-left of primary display, y increases downwards).
/// 2. AppKit global screen coordinates (origin at bottom-left of primary display, y increases upwards).
/// 3. AppKit window-local coordinates.
/// 4. SpriteKit scene coordinates (centered around character node).
///
/// Reliably handles multi-display configurations, displays placed to the left or above the main display,
/// negative coordinate origins, and scaling factors.
enum DesktopCoordinateSpace {

    // MARK: - Primary Screen Reference

    /// Retrieves primary display height used as the reflection axis between Quartz and AppKit.
    static func primaryScreenHeight(screens: [NSScreen] = NSScreen.screens) -> CGFloat {
        if let primary = screens.first(where: { $0.frame.origin == .zero }) {
            return primary.frame.height
        }
        return screens.first?.frame.height ?? 900
    }

    // MARK: - Quartz <-> AppKit Rect Conversions

    /// Converts a Quartz window bounding rectangle (top-left origin, y downwards)
    /// into AppKit global screen coordinates (bottom-left origin, y upwards).
    static func quartzRectToAppKit(
        _ quartzRect: CGRect,
        primaryScreenHeight: CGFloat
    ) -> NSRect {
        let appKitX = quartzRect.origin.x
        let appKitY = primaryScreenHeight - (quartzRect.origin.y + quartzRect.size.height)
        return NSRect(
            x: appKitX,
            y: appKitY,
            width: quartzRect.size.width,
            height: quartzRect.size.height
        )
    }

    /// Convenience overload using active screens.
    static func quartzRectToAppKit(_ quartzRect: CGRect) -> NSRect {
        quartzRectToAppKit(quartzRect, primaryScreenHeight: primaryScreenHeight())
    }

    /// Converts an AppKit global screen rectangle into Quartz display coordinates.
    static func appKitRectToQuartz(
        _ appKitRect: NSRect,
        primaryScreenHeight: CGFloat
    ) -> CGRect {
        let quartzX = appKitRect.origin.x
        let quartzY = primaryScreenHeight - (appKitRect.origin.y + appKitRect.size.height)
        return CGRect(
            x: quartzX,
            y: quartzY,
            width: appKitRect.size.width,
            height: appKitRect.size.height
        )
    }

    /// Convenience overload using active screens.
    static func appKitRectToQuartz(_ appKitRect: NSRect) -> CGRect {
        appKitRectToQuartz(appKitRect, primaryScreenHeight: primaryScreenHeight())
    }

    // MARK: - Quartz <-> AppKit Point Conversions

    /// Converts a Quartz screen point into AppKit global screen coordinates.
    static func quartzPointToAppKit(
        _ quartzPoint: CGPoint,
        primaryScreenHeight: CGFloat
    ) -> NSPoint {
        NSPoint(x: quartzPoint.x, y: primaryScreenHeight - quartzPoint.y)
    }

    /// Convenience overload using active screens.
    static func quartzPointToAppKit(_ quartzPoint: CGPoint) -> NSPoint {
        quartzPointToAppKit(quartzPoint, primaryScreenHeight: primaryScreenHeight())
    }

    /// Converts an AppKit global screen point into Quartz display coordinates.
    static func appKitPointToQuartz(
        _ appKitPoint: NSPoint,
        primaryScreenHeight: CGFloat
    ) -> CGPoint {
        CGPoint(x: appKitPoint.x, y: primaryScreenHeight - appKitPoint.y)
    }

    /// Convenience overload using active screens.
    static func appKitPointToQuartz(_ appKitPoint: NSPoint) -> CGPoint {
        appKitPointToQuartz(appKitPoint, primaryScreenHeight: primaryScreenHeight())
    }

    // MARK: - Screen <-> Scene Coordinates

    /// Converts an AppKit global screen coordinate into Cookie's local SpriteKit scene coordinate space.
    static func screenPointToScene(
        _ screenPoint: NSPoint,
        windowFrame: NSRect,
        sceneSize: CGSize
    ) -> CGPoint {
        let localX = screenPoint.x - windowFrame.midX
        let localY = screenPoint.y - windowFrame.midY
        return CGPoint(x: localX, y: localY)
    }

    /// Converts a point in Cookie's SpriteKit scene coordinate space to AppKit global screen coordinates.
    static func scenePointToScreen(
        _ scenePoint: CGPoint,
        windowFrame: NSRect
    ) -> NSPoint {
        NSPoint(x: windowFrame.midX + scenePoint.x, y: windowFrame.midY + scenePoint.y)
    }
}
