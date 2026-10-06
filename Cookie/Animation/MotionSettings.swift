import AppKit

/// System Reduced Motion setting, read live. When it is on, the animation
/// controller keeps every state transition and completion callback
/// working but renders poses statically, so Cookie remains readable
/// without non-essential movement. Changes take effect at the next
/// animation change, never mid-animation.
enum MotionSettings {
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}
