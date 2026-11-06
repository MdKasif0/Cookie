import Foundation
import CoreGraphics

/// A window as reported by the window server, reduced to what full-screen detection needs.
struct WindowSnapshot: Equatable {
    var ownerPID: Int32
    /// Normal app windows are layer 0. Menu bars, the Dock and the desktop are not.
    var layer: Int
    /// In global display coordinates, origin at the top left.
    var bounds: CGRect
}

enum FullscreenDetector {
    /// Whether another app has a window covering a whole display. That is how full-screen
    /// apps, games and slideshows look from outside.
    static func isFullscreenAppActive(windows: [WindowSnapshot], displays: [CGRect], ownPID: Int32, tolerance: CGFloat = 2) -> Bool {
        windows.contains { window in
            guard window.layer == 0, window.ownerPID != ownPID else { return false }
            return displays.contains { display in
                abs(window.bounds.minX - display.minX) <= tolerance
                    && abs(window.bounds.minY - display.minY) <= tolerance
                    && abs(window.bounds.width - display.width) <= tolerance
                    && abs(window.bounds.height - display.height) <= tolerance
            }
        }
    }
}
