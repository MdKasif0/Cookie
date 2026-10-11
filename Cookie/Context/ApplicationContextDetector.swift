import Foundation
import AppKit
import CoreGraphics
import os

/// Detects changes in the active macOS application using standard, non-intrusive APIs.
/// Tracks only the frontmost app's metadata without inspecting documents, window contents, or keystrokes.
@MainActor
final class ApplicationContextDetector: ObservableObject {
    @Published private(set) var currentContext: ApplicationContext = .unknown
    @Published private(set) var previousContext: ApplicationContext?

    /// Seam for providing the frontmost application in deterministic tests.
    var frontmostAppProvider: () -> (bundleId: String?, name: String?, pid: pid_t?, isCookie: Bool)? = {
        guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
        let currentPid = ProcessInfo.processInfo.processIdentifier
        let isCookie = (front.processIdentifier == currentPid)
        return (front.bundleIdentifier, front.localizedName, front.processIdentifier, isCookie)
    }

    /// Seam for time.
    var now: () -> Date = { Date() }

    /// Optional reference to the window provider to correlate frontmost window bounds.
    weak var windowProvider: WindowEnvironmentProvider?

    /// Notification observer token.
    private var activateObserver: NSObjectProtocol?
    private var deactivateObserver: NSObjectProtocol?
    private let log = Logger(subsystem: "com.cookie.mac", category: "ApplicationContext")

    /// Callback invoked when an active application switch is detected.
    var onApplicationSwitched: ((ApplicationContext) -> Void)?

    init(windowProvider: WindowEnvironmentProvider? = nil) {
        self.windowProvider = windowProvider
        refreshContext()
        setupNotificationObservers()
    }

    deinit {
        if let activateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activateObserver)
        }
        if let deactivateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(deactivateObserver)
        }
    }

    private func setupNotificationObservers() {
        activateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshContext()
            }
        }

        deactivateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshContext()
            }
        }
    }

    /// Evaluates the frontmost application context and publishes changes.
    @discardableResult
    func refreshContext() -> ApplicationContext {
        let currentTime = now()
        guard let front = frontmostAppProvider() else {
            let unknownContext = ApplicationContext(
                state: .unknown,
                bundleIdentifier: nil,
                applicationName: nil,
                processIdentifier: nil,
                category: .unknown,
                isCookieActive: false,
                frontmostWindowBounds: nil,
                timestamp: currentTime
            )
            updateContext(to: unknownContext)
            return unknownContext
        }

        let isCookie = front.isCookie
        let bundleId = front.bundleId
        let name = front.name
        let pid = front.pid
        let category = ApplicationCategory.classify(bundleId: bundleId, appName: name)

        let state: DesktopContextState
        if isCookie {
            state = .cookieFrontmost
        } else if category == .fileManager {
            state = .desktopVisible
        } else {
            state = .externalAppFrontmost
        }

        // Match observable window bounds if available in WindowEnvironmentProvider
        var matchedBounds: NSRect?
        if let pid, let windows = windowProvider?.candidateWindows {
            matchedBounds = windows.first(where: { $0.ownerPID == pid })?.bounds
        }

        let newContext = ApplicationContext(
            state: state,
            bundleIdentifier: bundleId,
            applicationName: name,
            processIdentifier: pid,
            category: category,
            isCookieActive: isCookie,
            frontmostWindowBounds: matchedBounds,
            timestamp: currentTime
        )

        updateContext(to: newContext)
        return newContext
    }

    private func updateContext(to newContext: ApplicationContext) {
        guard newContext != currentContext else { return }
        log.info("Active application context changed: \(newContext.applicationName ?? "Unknown", privacy: .public) [\(newContext.category.displayName, privacy: .public)] (isCookie: \(newContext.isCookieActive, privacy: .public))")
        previousContext = currentContext
        currentContext = newContext
        onApplicationSwitched?(newContext)
    }
}
