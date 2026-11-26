import Foundation

/// The short tour Cookie gives of her helpers: right after the welcome, once after the update that
/// added them, and whenever it's chosen from her menu. Each step can be tried on the spot.
enum HelpersTour {
    enum Action: Equatable {
        case newReminder
        case pinNote
        case openSettings
    }

    struct Step: Equatable {
        let title: String
        let text: String
        /// The button that tries the helper right away, if there's something to try.
        let tryTitle: String?
        let action: Action?
        let reaction: CookieReaction
    }

    /// The note she pins when "Pin a note" is chosen.
    static let sampleNote = "Hi! I'm a sticky note. Drag me anywhere, or double-click to edit."

    static func steps(name: String) -> [Step] {
        [
            Step(title: "Reminders",
                 text: "Need a nudge later? I'll come find you and meow when it's time, even over a full-screen app.",
                 tryTitle: "Set a Reminder", action: .newReminder, reaction: .happy),
            Step(title: "Notes and to-dos",
                 text: "I can pin sticky notes to your desktop and keep a to-do list. Every task you finish brings us closer.",
                 tryTitle: "Pin a Note", action: .pinNote, reaction: .surprised),
            Step(title: "Drop files on me",
                 text: "Drag any file onto me and I'll move it, copy it or zip it for you.",
                 tryTitle: nil, action: nil, reaction: .meow),
            Step(title: "Chat with \(name)",
                 text: "Add your own Claude API key under Settings → Power Tools and we can talk. It's off until you do.",
                 tryTitle: "Open Settings", action: .openSettings, reaction: .shy),
            Step(title: "That's the tour!",
                 text: "Right-click me any time for all of this and more. Break nudges, focus guard and bedtime are in Settings → Helpers.",
                 tryTitle: nil, action: nil, reaction: .happy),
        ]
    }

    /// She only starts the tour on her own at a calm moment: on screen, with no full-screen app,
    /// no quiet mode and no focus session. Otherwise she waits for another launch.
    static func canStartOnItsOwn(hasCompletedWelcome: Bool, hasSeenTour: Bool, isVisible: Bool,
                                 isQuiet: Bool, isFocusing: Bool) -> Bool {
        hasCompletedWelcome && !hasSeenTour && isVisible && !isQuiet && !isFocusing
    }
}
