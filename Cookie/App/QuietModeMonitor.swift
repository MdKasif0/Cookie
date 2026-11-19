import AppKit
import CoreGraphics

/// Decides when Cookie should step aside: while another app is full screen, which covers games,
/// slideshows and video. Summoning her overrides it for a short while.
@MainActor
final class QuietModeMonitor: ObservableObject {
    @Published private(set) var isQuiet = false
    /// Quiet mode you turned on yourself (from a link, Shortcuts or the menu), and when it ends.
    /// `.distantFuture` means until you turn it off.
    @Published private(set) var manualQuietUntil: Date?

    private let store: CookieStore
    private var timer: Timer?
    private var overrideUntil = Date.distantPast

    var now: () -> Date = { Date() }
    var windowSource: () -> [WindowSnapshot] = QuietModeMonitor.systemWindows
    var displaySource: () -> [CGRect] = QuietModeMonitor.systemDisplays
    var ownPID: Int32 = ProcessInfo.processInfo.processIdentifier

    init(store: CookieStore) {
        self.store = store
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        evaluate()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Lets her stay visible for `seconds` even if a full-screen app is up.
    func grantOverride(seconds: TimeInterval) {
        overrideUntil = now().addingTimeInterval(seconds)
        evaluate()
    }

    var isManuallyQuiet: Bool {
        guard let until = manualQuietUntil else { return false }
        return now() < until
    }

    /// Turns quiet mode on, for `minutes` or until turned off.
    func setManualQuiet(_ on: Bool, minutes: Int? = nil) {
        if on {
            manualQuietUntil = minutes.map { now().addingTimeInterval(TimeInterval($0) * 60) } ?? .distantFuture
            overrideUntil = .distantPast
        } else {
            manualQuietUntil = nil
        }
        evaluate()
    }

    func evaluate() {
        if let until = manualQuietUntil, now() >= until { manualQuietUntil = nil }
        // A reminder or summon briefly overrides both kinds of quiet.
        var quiet = isManuallyQuiet && now() >= overrideUntil
        if !quiet, store.profile.settings.hideInFullscreen, now() >= overrideUntil {
            quiet = FullscreenDetector.isFullscreenAppActive(
                windows: windowSource(), displays: displaySource(), ownPID: ownPID
            )
        }
        if quiet != isQuiet { isQuiet = quiet }
    }

    // MARK: - System sources

    /// The window server's on-screen windows. Bounds, layer and owner need no special permission.
    static func systemWindows() -> [WindowSnapshot] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary) else { return nil }
            return WindowSnapshot(ownerPID: pid, layer: layer, bounds: bounds)
        }
    }

    static func systemDisplays() -> [CGRect] {
        NSScreen.screens.compactMap { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
                .map { CGDisplayBounds($0) }
        }
    }
}
