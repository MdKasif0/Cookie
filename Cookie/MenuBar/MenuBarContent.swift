import SwiftUI

/// Cookie's menu bar menu — simple and polished. The name headers the
/// menu, companion commands sit in the middle, and the app controls at
/// the bottom.
struct MenuBarContent: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var store: CookieStore

    var body: some View {
        Text(store.profile.displayName)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
        Divider()
        if store.profile.isCompanionVisible {
            Button("Hide Cookie") { environment.toggleCompanion() }
        } else {
            Button("Show Cookie") { environment.toggleCompanion() }
        }
        Divider()
        Button("Pet Cookie") { environment.petCookie() }
        Button("Feed Cookie") { environment.feedCookie() }
        Button("Play") { environment.playWithCookie() }
        Divider()
        Button("Customize Cookie…") { environment.showCustomization() }
            .keyboardShortcut("k", modifiers: .command)
        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",", modifiers: .command)
        Divider()
        Button("Quit Cookie") { environment.quit() }
            .keyboardShortcut("q", modifiers: .command)
    }
}
