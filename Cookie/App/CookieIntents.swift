import AppIntents
import AppKit

/// Hands commands from links and Shortcuts to the running app.
@MainActor
enum CookieCommandRouter {
    static weak var environment: AppEnvironment?

    /// Runs the command in this process, or opens its `cookie://` link so a fresh launch picks it up.
    static func run(_ command: CookieCommand) {
        if let environment {
            environment.perform(command)
        } else {
            NSWorkspace.shared.open(command.url)
        }
    }
}

// MARK: - Actions

struct SayIntent: AppIntent {
    static let title: LocalizedStringResource = "Make Cookie Say Something"
    static let description = IntentDescription("Cookie shows your text in a speech bubble.")

    @Parameter(title: "Text")
    var text: String

    static var parameterSummary: some ParameterSummary { Summary("Cookie says \(\.$text)") }

    @MainActor
    func perform() async throws -> some IntentResult {
        CookieCommandRouter.run(.say(String(text.prefix(CookieCommand.maximumText))))
        return .result()
    }
}

struct RemindIntent: AppIntent {
    static let title: LocalizedStringResource = "Set a Cookie Reminder"
    static let description = IntentDescription("Cookie comes to your cursor and reminds you after the time you choose.")

    @Parameter(title: "Reminder", default: "")
    var text: String

    @Parameter(title: "Minutes", default: 20, inclusiveRange: (1, 1440))
    var minutes: Int

    static var parameterSummary: some ParameterSummary { Summary("Remind me in \(\.$minutes) minutes to \(\.$text)") }

    @MainActor
    func perform() async throws -> some IntentResult {
        CookieCommandRouter.run(.remind(text: String(text.prefix(CookieCommand.maximumText)), minutes: minutes))
        return .result()
    }
}

struct StartFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a Focus Session"
    static let description = IntentDescription("Cookie naps beside you, then tells you when it's time for a break.")

    @Parameter(title: "Minutes", default: 25, inclusiveRange: (5, 180))
    var minutes: Int

    static var parameterSummary: some ParameterSummary { Summary("Focus for \(\.$minutes) minutes") }

    @MainActor
    func perform() async throws -> some IntentResult {
        CookieCommandRouter.run(.startFocus(minutes: minutes))
        return .result()
    }
}

struct StopFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop the Focus Session"

    @MainActor
    func perform() async throws -> some IntentResult {
        CookieCommandRouter.run(.stopFocus)
        return .result()
    }
}

struct QuietModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Cookie's Quiet Mode"
    static let description = IntentDescription("Hides Cookie and holds her nudges. Reminders still get through.")

    @Parameter(title: "Quiet", default: true)
    var on: Bool

    @Parameter(title: "Minutes", description: "Leave empty to stay quiet until you turn it off.", inclusiveRange: (1, 1440))
    var minutes: Int?

    static var parameterSummary: some ParameterSummary {
        When(\.$on, .equalTo, true) {
            Summary("Turn quiet mode \(\.$on) for \(\.$minutes) minutes")
        } otherwise: {
            Summary("Turn quiet mode \(\.$on)")
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        CookieCommandRouter.run(.quiet(on: on, minutes: on ? minutes : nil))
        return .result()
    }
}

struct AddTodoIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a Task to Cookie's List"

    @Parameter(title: "Task")
    var text: String

    static var parameterSummary: some ParameterSummary { Summary("Add \(\.$text) to Cookie's list") }

    @MainActor
    func perform() async throws -> some IntentResult {
        CookieCommandRouter.run(.addTodo(String(text.prefix(CookieCommand.maximumText))))
        return .result()
    }
}

struct AddNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Pin a Sticky Note"

    @Parameter(title: "Note")
    var text: String

    static var parameterSummary: some ParameterSummary { Summary("Pin \(\.$text) on the desktop") }

    @MainActor
    func perform() async throws -> some IntentResult {
        CookieCommandRouter.run(.addNote(String(text.prefix(CookieCommand.maximumText))))
        return .result()
    }
}

struct SummonIntent: AppIntent {
    static let title: LocalizedStringResource = "Call Cookie Over"

    @MainActor
    func perform() async throws -> some IntentResult {
        CookieCommandRouter.run(.summon)
        return .result()
    }
}

// MARK: - Suggested shortcuts

struct CookieShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartFocusIntent(),
            phrases: ["Start a focus session with \(.applicationName)", "Focus with \(.applicationName)"],
            shortTitle: "Focus",
            systemImageName: "moon.zzz"
        )
        AppShortcut(
            intent: QuietModeIntent(),
            phrases: ["Make \(.applicationName) quiet", "Quiet \(.applicationName)"],
            shortTitle: "Quiet Mode",
            systemImageName: "speaker.slash"
        )
        AppShortcut(
            intent: RemindIntent(),
            phrases: ["Set a reminder with \(.applicationName)"],
            shortTitle: "Reminder",
            systemImageName: "bell"
        )
        AppShortcut(
            intent: SummonIntent(),
            phrases: ["Call \(.applicationName)", "Summon \(.applicationName)"],
            shortTitle: "Call Cookie",
            systemImageName: "pawprint"
        )
    }
}
