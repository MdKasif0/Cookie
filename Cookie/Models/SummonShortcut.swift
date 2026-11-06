import Foundation
import Carbon.HIToolbox

/// The keyboard shortcuts offered for calling Cookie to your cursor. A fixed set keeps
/// the choice simple and avoids clashes with other apps' recorders.
enum SummonShortcut: String, CaseIterable, Codable, Identifiable {
    case controlOptionC
    case controlOptionSpace
    case commandOptionC
    case controlOptionCommandC
    case off

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .controlOptionC: return "⌃⌥C"
        case .controlOptionSpace: return "⌃⌥Space"
        case .commandOptionC: return "⌘⌥C"
        case .controlOptionCommandC: return "⌃⌥⌘C"
        case .off: return "Off"
        }
    }

    /// Carbon virtual key code, or nil when the shortcut is off.
    var keyCode: UInt32? {
        switch self {
        case .controlOptionC, .commandOptionC, .controlOptionCommandC: return UInt32(kVK_ANSI_C)
        case .controlOptionSpace: return UInt32(kVK_Space)
        case .off: return nil
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .controlOptionC, .controlOptionSpace: return UInt32(controlKey | optionKey)
        case .commandOptionC: return UInt32(cmdKey | optionKey)
        case .controlOptionCommandC: return UInt32(controlKey | optionKey | cmdKey)
        case .off: return 0
        }
    }
}
