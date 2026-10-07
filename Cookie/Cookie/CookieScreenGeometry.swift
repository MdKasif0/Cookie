import AppKit

/// Pure geometry for keeping Cookie visible across any display setup:
/// clamping into the union of all screens' visible areas, restoring a
/// saved position that may no longer be on any display, and the friendly
/// default spot.
enum CookieScreenGeometry {
    /// Base panel edge before the Cookie size setting scales it.
    static let basePanelDimension: CGFloat = 160

    /// Panel size for a given Cookie size setting.
    static func basePanelSize(for cookieSize: Double) -> CGSize {
        CGSize(width: basePanelDimension * cookieSize, height: basePanelDimension * cookieSize)
    }

    static func visibleUnion(of screens: [NSScreen]) -> NSRect? {
        guard var union = screens.first?.visibleFrame else { return nil }
        for screen in screens.dropFirst() {
            union = union.union(screen.visibleFrame)
        }
        return union
    }

    /// Keeps the window's center inside the union of all visible screen
    /// areas. Cookie may hang partway off an edge while dragged, but her
    /// center always stays reachable.
    static func safeOrigin(for frame: NSRect, in screens: [NSScreen]) -> NSPoint {
        guard let union = visibleUnion(of: screens) else { return frame.origin }
        let margin: CGFloat = 24
        let centerX = min(max(frame.midX, union.minX + margin), union.maxX - margin)
        let centerY = min(max(frame.midY, union.minY + margin), union.maxY - margin)
        return NSPoint(x: centerX - frame.width / 2, y: centerY - frame.height / 2)
    }

    /// Restores a saved position. Positions whose center is still on some
    /// display are kept (clamped to be reachable); anything stranded by a
    /// disconnected display falls back to the friendly default spot.
    static func restoreOrigin(saved: CGPoint?, size: CGSize, screens: [NSScreen]) -> NSPoint {
        guard let saved else { return defaultOrigin(size: size, screens: screens) }
        let frame = NSRect(origin: NSPoint(x: saved.x, y: saved.y), size: size)
        if let union = visibleUnion(of: screens), union.contains(NSPoint(x: frame.midX, y: frame.midY)) {
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
