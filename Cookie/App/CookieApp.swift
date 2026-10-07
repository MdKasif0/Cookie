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
    }
}
