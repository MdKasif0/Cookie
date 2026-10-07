import AppKit

/// Pure geometry for keeping Cookie visible across any display setup:
/// clamping into active screens, handling monitor disconnects, resolution
/// changes, and restoring saved coordinates safely.
enum CookieScreenGeometry {
    /// Base panel edge before the Cookie size setting scales it.
    static let basePanelDimension: CGFloat = 160

    /// Panel size for a given Cookie size setting.
    static func basePanelSize(for cookieSize: Double) -> CGSize {
        CGSize(width: basePanelDimension * cookieSize, height: basePanelDimension * cookieSize)
    }

    /// Keeps the window's center inside the nearest or active screen's visible area.
    /// Protects against multi-monitor gaps, disconnected external displays, and resolution shifts.
    static func safeOrigin(for frame: NSRect, in screens: [NSScreen]) -> NSPoint {
        guard !screens.isEmpty else { return frame.origin }
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let margin: CGFloat = 20

        // 1. If center is already on an active screen, clamp within that specific screen's visible frame.
        if let currentScreen = screens.first(where: { $0.visibleFrame.contains(center) }) {
            let vis = currentScreen.visibleFrame
            let clampedX = min(max(frame.midX, vis.minX + margin), vis.maxX - margin)
            let clampedY = min(max(frame.midY, vis.minY + margin), vis.maxY - margin)
            return NSPoint(x: clampedX - frame.width / 2, y: clampedY - frame.height / 2)
        }

        // 2. Center is off-screen (e.g. monitor was unplugged). Find the closest screen by center distance.
        let targetScreen = screens.min(by: { s1, s2 in
            let c1 = NSPoint(x: s1.visibleFrame.midX, y: s1.visibleFrame.midY)
            let c2 = NSPoint(x: s2.visibleFrame.midX, y: s2.visibleFrame.midY)
            let d1 = hypot(center.x - c1.x, center.y - c1.y)
            let d2 = hypot(center.x - c2.x, center.y - c2.y)
            return d1 < d2
        }) ?? (NSScreen.main ?? screens[0])

        let vis = targetScreen.visibleFrame
        let clampedX = min(max(frame.midX, vis.minX + margin), vis.maxX - margin)
        let clampedY = min(max(frame.midY, vis.minY + margin), vis.maxY - margin)
        return NSPoint(x: clampedX - frame.width / 2, y: clampedY - frame.height / 2)
    }

    /// Restores a saved position. Positions whose center is still on some
    /// active display are kept (clamped to be reachable); anything stranded by a
    /// disconnected display falls back cleanly to the main screen.
    static func restoreOrigin(saved: CGPoint?, size: CGSize, screens: [NSScreen]) -> NSPoint {
        guard let saved else { return defaultOrigin(size: size, screens: screens) }
        let frame = NSRect(origin: NSPoint(x: saved.x, y: saved.y), size: size)
        let center = NSPoint(x: frame.midX, y: frame.midY)

        if screens.contains(where: { $0.visibleFrame.contains(center) }) {
            return safeOrigin(for: frame, in: screens)
        }
        return defaultOrigin(size: size, screens: screens)
    }

    /// A friendly default: bottom center of the main screen.
    static func defaultOrigin(size: CGSize, screens: [NSScreen]) -> NSPoint {
        guard let visible = screens.first?.visibleFrame ?? NSScreen.main?.visibleFrame else {
            return .zero
        }
        return NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 96)
    }
}
