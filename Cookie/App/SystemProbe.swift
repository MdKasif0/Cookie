import Foundation
import IOKit.ps
import Network
import EventKit

/// Reads the Mac's state for the system watcher. Battery, load, disk space and connectivity are
/// all public and need no permission.
final class SystemProbe {
    private let pathMonitor = NWPathMonitor()
    private let lock = NSLock()
    private var online: Bool?

    init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.online = path.status == .satisfied
            self.lock.unlock()
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.cookie.mac.network"))
    }

    deinit { pathMonitor.cancel() }

    func snapshot() -> SystemSnapshot {
        var snapshot = SystemSnapshot()
        (snapshot.batteryPercent, snapshot.isCharging) = Self.battery()
        snapshot.cpuLoad = Self.cpuLoad()
        (snapshot.diskFreeBytes, snapshot.diskTotalBytes) = Self.disk()
        lock.lock()
        snapshot.isOnline = online
        lock.unlock()
        return snapshot
    }

    /// The internal battery, if there is one. Desktops return nil.
    static func battery() -> (Int?, Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return (nil, false) }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let onAC = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let charging = (description[kIOPSIsChargingKey] as? Bool ?? false) || onAC
            return (Int((Double(current) / Double(max) * 100).rounded()), charging)
        }
        return (nil, false)
    }

    /// The one-minute load average divided by the number of cores.
    static func cpuLoad() -> Double? {
        var loads = [Double](repeating: 0, count: 3)
        guard getloadavg(&loads, 3) >= 1 else { return nil }
        let cores = Double(max(1, ProcessInfo.processInfo.activeProcessorCount))
        return loads[0] / cores
    }

    static func disk() -> (Int64?, Int64?) {
        let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey
        ])
        return (values?.volumeAvailableCapacityForImportantUsage, values?.volumeTotalCapacity.map(Int64.init))
    }
}

/// Calendar access for heads-ups. Only asks when you turn the feature on.
@MainActor
final class CalendarSource: ObservableObject {
    @Published private(set) var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    private let store = EKEventStore()

    var hasAccess: Bool { status == .fullAccess }
    var wasDenied: Bool { status == .denied || status == .restricted || status == .writeOnly }

    func refreshStatus() {
        status = EKEventStore.authorizationStatus(for: .event)
    }

    func requestAccess() async -> Bool {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        refreshStatus()
        return granted
    }

    /// Timed events starting in the next `minutes`, from every calendar.
    func upcoming(from now: Date, minutes: Int) -> [UpcomingEvent] {
        guard hasAccess else { return [] }
        let end = now.addingTimeInterval(TimeInterval(minutes + 1) * 60)
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        return store.events(matching: predicate).map {
            UpcomingEvent(id: $0.eventIdentifier ?? $0.calendarItemIdentifier, title: $0.title ?? "", start: $0.startDate, isAllDay: $0.isAllDay)
        }
    }
}

/// Folder access for the downloads watcher and the screenshot tidy-up.
enum DeskFiles {
    static var downloadsFolder: URL? {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }

    /// Where screenshots are saved: the location chosen in the Screenshot app, else the Desktop.
    static var screenshotFolder: URL? {
        if let custom = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"), !custom.isEmpty {
            let url = URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
    }

    static func listing(of folder: URL) -> [String: Int64] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: [.skipsHiddenFiles]) else { return [:] }
        var result: [String: Int64] = [:]
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            result[url.lastPathComponent] = Int64(values?.fileSize ?? 0) + (values?.isDirectory == true ? 1 : 0)
        }
        return result
    }

    static func screenshotCandidates(now: Date = Date()) -> (folder: URL, names: [String])? {
        guard let folder = screenshotFolder,
              let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return nil }
        let files = urls.map { url in
            (name: url.lastPathComponent,
             modified: (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? now)
        }
        return (folder, ScreenshotTidy.candidates(files, now: now))
    }

    /// Moves the named files into a "Screenshots" folder beside them. Nothing is deleted.
    /// Returns how many were moved.
    @discardableResult
    static func tidyScreenshots(_ names: [String], in folder: URL) -> Int {
        let destination = folder.appendingPathComponent(ScreenshotTidy.folderName, isDirectory: true)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            return 0
        }
        var existing = Set((try? fm.contentsOfDirectory(atPath: destination.path)) ?? [])
        var moved = 0
        for name in names {
            let target = ScreenshotTidy.uniqueName(name, existing: existing)
            do {
                try fm.moveItem(at: folder.appendingPathComponent(name), to: destination.appendingPathComponent(target))
                existing.insert(target)
                moved += 1
            } catch {
                continue
            }
        }
        return moved
    }
}
