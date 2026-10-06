import AppKit
import CoreGraphics

/// Basic facts about a window currently on screen.
struct DesktopWindowInfo: Equatable {
    let processIdentifier: pid_t
    let ownerName: String?
    let bounds: CGRect
}

/// Read-only observation of the surrounding desktop. This is the seam for
/// future playful companion behaviors — e.g. perching beside a window,
/// glancing toward the active app, or settling into gaps between windows.
///
/// Cookie is strictly non-intrusive: this scanner only *looks* at the
/// window list. Nothing here ever moves, resizes, raises, minimizes, or
/// closes another application's window, and no behavior may use it to do
/// so later.
enum DesktopWindowScanner {
    /// Normal-level windows currently visible on screen, excluding
    /// desktop elements and (by default) Cookie's own windows.
    static func onScreenWindows(includingSelf: Bool = false) -> [DesktopWindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let selfPID = ProcessInfo.processInfo.processIdentifier
        return list.compactMap { entry in
            guard let pid = entry[kCGWindowOwnerPID as String] as? Int else { return nil }
            if !includingSelf && pid == selfPID { return nil }
            guard (entry[kCGWindowLayer as String] as? Int) == 0 else { return nil }
            guard let bounds = entry[kCGWindowBounds as String] as? [String: NSNumber],
                  let x = bounds["X"]?.doubleValue,
                  let y = bounds["Y"]?.doubleValue,
                  let width = bounds["Width"]?.doubleValue,
                  let height = bounds["Height"]?.doubleValue,
                  width > 0, height > 0 else { return nil }
            return DesktopWindowInfo(
                processIdentifier: pid_t(pid),
                ownerName: entry[kCGWindowOwnerName as String] as? String,
                bounds: CGRect(x: x, y: y, width: width, height: height)
            )
        }
    }
}
