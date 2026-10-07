import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        // Debug tools for art review; each exports and exits.
        let arguments = ProcessInfo.processInfo.arguments
        var debugConfig = CookieAppearanceConfig()
        if let fur = ProcessInfo.processInfo.environment["COOKIE_FUR_COLOR"],
           let color = FurColor(rawValue: fur) {
            debugConfig.furColor = color
        }
        if arguments.contains("--export-cookie-frames") {
            let directory = URL(fileURLWithPath: "/tmp/cookie-frames")
            ReferenceImageSource.exportFrames(to: directory, config: debugConfig)
            print("Cookie frames exported to \(directory.path)")
            exit(0)
        }
        if arguments.contains("--export-cookie-hitmask") {
            let url = URL(fileURLWithPath: "/tmp/cookie-hitmask.png")
            CookieHitTester(canvasSize: CookieSpriteRenderer.canvasSize)?.exportMask(to: url)
            print("Cookie hit mask exported to \(url.path)")
            exit(0)
        }
        if arguments.contains("--export-cookie-expressions") {
            let directory = URL(fileURLWithPath: "/tmp/cookie-expressions")
            ExpressionArtSource.exportAll(to: directory, config: debugConfig)
            print("Cookie expressions exported to \(directory.path)")
            exit(0)
        }
        #endif
        // Explicitly set dynamic dock icon to guarantee immediate display on launch
        if let iconImage = NSImage(named: "AppIcon") ?? NSImage(contentsOfFile: Bundle.main.path(forResource: "AppIcon", ofType: "icns") ?? "") {
            NSApp.applicationIconImage = iconImage
        }
        environment.start()
    }

    /// Cookie lives on the desktop; closing windows must not quit the app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        environment.handleAppReopen()
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        environment.createCookieMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment.shutdown()
    }
}
