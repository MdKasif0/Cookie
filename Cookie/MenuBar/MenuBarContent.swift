import SwiftUI

/// Cookie's menu bar menu: quick access to the companion, settings, and
/// quitting — the app's home base when no window is open.
struct MenuBarContent: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var store: CookieStore

    var body: some View {
        Text(store.profile.displayName)
        Divider()
        Button(store.profile.isCompanionVisible ? "Hide Cookie" : "Show Cookie") {
            environment.toggleCompanion()
        }
        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",", modifiers: .command)
        Divider()
        Button("Quit Cookie") {
            environment.quit()
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
