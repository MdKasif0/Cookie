import SwiftUI

@main
struct CookieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.environment)
                .environmentObject(appDelegate.environment.store)
        }
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(appDelegate.environment)
                .environmentObject(appDelegate.environment.store)
        } label: {
            Image(systemName: "cat.fill")
        }
        .menuBarExtraStyle(.menu)
    }
}
