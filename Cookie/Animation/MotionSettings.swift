import AppKit

/// System Reduced Motion handling with three modes: follow the system
/// setting, always reduce, or never reduce. When reduced, the animation
/// controller keeps every state transition and callback working but
/// renders poses statically.
enum MotionSettings {
    static var mode: ReducedMotionMode = .system

    static var reduceMotion: Bool {
        switch mode {
        case .always: return true
        case .never: return false
        case .system: return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
    }
}
