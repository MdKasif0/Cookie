import Foundation
import CoreGraphics

// Pure models for the everyday helpers: the system watcher, calendar heads-ups, sticky notes,
// the to-do list, and the downloads and screenshot helpers. No clocks, no file system.

// MARK: - System watcher

/// One look at the Mac. `nil` means "couldn't tell", which never raises an alert.
struct SystemSnapshot: Equatable {
    var batteryPercent: Int?
    var isCharging: Bool = false
    /// Load average over all cores, 0 = idle, 1 = every core busy.
    var cpuLoad: Double?
    var diskFreeBytes: Int64?
    var diskTotalBytes: Int64?
    var isOnline: Bool?
}

enum SystemAlert: Equatable {
    case lowBattery(percent: Int)
    case criticalBattery(percent: Int)
    case cpuBusy
    case diskAlmostFull(freeGB: Int)
    case offline
    case backOnline

    var kind: SystemAlertKind {
        switch self {
        case .lowBattery, .criticalBattery: return .battery
        case .cpuBusy: return .cpu
        case .diskAlmostFull: return .disk
        case .offline, .backOnline: return .network
        }
    }

    /// Important enough to come over a full-screen app.
    var isUrgent: Bool {
        if case .criticalBattery = self { return true }
        return false
    }

    func message(name: String) -> String {
        switch self {
        case .lowBattery(let percent): return "Battery's at \(percent)%. Time to find the charger?"
        case .criticalBattery(let percent): return "Only \(percent)% battery left! Plug in soon or save your work."
        case .cpuBusy: return "Your Mac is working really hard. Something might be stuck."
        case .diskAlmostFull(let freeGB): return "Your disk is nearly full: only \(freeGB) GB left."
        case .offline: return "Uh oh, the internet just dropped."
        case .backOnline: return "We're back online!"
        }
    }
}

enum SystemAlertKind: String, CaseIterable, Identifiable, Codable {
    case battery, cpu, disk, network

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .battery: return "Low battery"
        case .cpu: return "CPU maxed out for a few minutes"
        case .disk: return "Disk almost full"
        case .network: return "Internet connection drops"
        }
    }
}

/// Decides what is worth saying, with enough memory not to repeat itself.
struct SystemWatch: Equatable {
    static let lowBattery = 20
    static let criticalBattery = 10
    /// Battery alerts re-arm once you charge past this.
    static let batteryRearm = 30
    static let busyLoad = 0.9
    /// Samples in a row above `busyLoad` before she says anything.
    static let busySamples = 9
    static let cpuCooldown: TimeInterval = 30 * 60
    static let diskCooldown: TimeInterval = 24 * 3600
    static let lowDiskBytes: Int64 = 10 * 1_000_000_000
    static let lowDiskFraction = 0.05

    private(set) var saidLowBattery = false
    private(set) var saidCriticalBattery = false
    private(set) var busyStreak = 0
    private(set) var lastCPUAlert = Date.distantPast
    private(set) var lastDiskAlert = Date.distantPast
    private(set) var wasOnline: Bool?
    private(set) var saidOffline = false

    /// Folds in a new snapshot and returns what to say, most important first.
    mutating func update(with snapshot: SystemSnapshot, at now: Date, enabled: Set<SystemAlertKind>) -> [SystemAlert] {
        var alerts: [SystemAlert] = []

        if let percent = snapshot.batteryPercent {
            if snapshot.isCharging || percent >= Self.batteryRearm {
                saidLowBattery = false
                saidCriticalBattery = false
            } else if percent <= Self.criticalBattery, !saidCriticalBattery {
                saidCriticalBattery = true
                saidLowBattery = true
                if enabled.contains(.battery) { alerts.append(.criticalBattery(percent: percent)) }
            } else if percent <= Self.lowBattery, !saidLowBattery {
                saidLowBattery = true
                if enabled.contains(.battery) { alerts.append(.lowBattery(percent: percent)) }
            }
        }

        if let load = snapshot.cpuLoad {
            busyStreak = load >= Self.busyLoad ? busyStreak + 1 : 0
            if busyStreak >= Self.busySamples, now.timeIntervalSince(lastCPUAlert) >= Self.cpuCooldown {
                lastCPUAlert = now
                busyStreak = 0
                if enabled.contains(.cpu) { alerts.append(.cpuBusy) }
            }
        }

        if let free = snapshot.diskFreeBytes, let total = snapshot.diskTotalBytes, total > 0 {
            let low = free < Self.lowDiskBytes || Double(free) / Double(total) < Self.lowDiskFraction
            if low, now.timeIntervalSince(lastDiskAlert) >= Self.diskCooldown {
                lastDiskAlert = now
                if enabled.contains(.disk) { alerts.append(.diskAlmostFull(freeGB: Int(free / 1_000_000_000))) }
            }
        }

        if let online = snapshot.isOnline {
            if wasOnline == true, !online {
                saidOffline = enabled.contains(.network)
                if saidOffline { alerts.append(.offline) }
            } else if wasOnline == false, online, saidOffline {
                saidOffline = false
                alerts.append(.backOnline)
            }
            wasOnline = online
        }

        return alerts.sorted { $0.isUrgent && !$1.isUrgent }
    }
}

// MARK: - Calendar

struct UpcomingEvent: Equatable {
    var id: String
    var title: String
    var start: Date
    var isAllDay: Bool = false
}

enum CalendarHeadsUp {
    static let leadOptions = [1, 2, 5, 10, 15]

    /// Events starting within `leadMinutes` that haven't been announced yet, soonest first.
    static func eventsToAnnounce(_ events: [UpcomingEvent], now: Date, leadMinutes: Int, announced: Set<String>) -> [UpcomingEvent] {
        let lead = TimeInterval(max(1, leadMinutes)) * 60
        return events
            .filter { !$0.isAllDay && !announced.contains(key(for: $0)) }
            .filter { $0.start > now && $0.start.timeIntervalSince(now) <= lead }
            .sorted { $0.start < $1.start }
    }

    /// A repeating meeting has one id for every occurrence, so the start time is part of the key.
    static func key(for event: UpcomingEvent) -> String {
        "\(event.id)@\(Int(event.start.timeIntervalSince1970))"
    }

    static func message(for event: UpcomingEvent, now: Date) -> String {
        let minutes = max(1, Int((event.start.timeIntervalSince(now) / 60).rounded(.up)))
        let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let what = title.isEmpty ? "Your next event" : title
        return minutes == 1 ? "\(what) starts in a minute!" : "\(what) in \(minutes) minutes."
    }
}

// MARK: - Sticky notes

struct StickyNote: Codable, Equatable, Identifiable {
    var id = UUID()
    var text: String
    var color: StickyColor = .yellow
    /// Top-left corner in screen coordinates; nil until it has been placed.
    var origin: CGPoint?
    var createdAt = Date()

    static let maximumLength = 280
}

enum StickyColor: String, Codable, CaseIterable, Identifiable {
    case yellow, pink, blue, green

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    var hex: String {
        switch self {
        case .yellow: return "#FFF1A8"
        case .pink: return "#FFD3E2"
        case .blue: return "#CFE6FF"
        case .green: return "#D6F5CF"
        }
    }

    var next: StickyColor {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

// MARK: - To-do list

struct TodoItem: Codable, Equatable, Identifiable {
    var id = UUID()
    var text: String
    var isDone = false
    var createdAt = Date()
    var doneAt: Date?

    static let maximumCount = 12

    static func cheer(name: String) -> String {
        ["Nice work!", "One down!", "\(name) is proud of you!", "Look at you go!"].randomElement()!
    }
}

// MARK: - Downloads

/// Notices files that land in a folder and finish growing. Partial downloads are ignored until
/// the browser renames them, and nothing already there when watching starts is announced.
struct DownloadWatch: Equatable {
    static let partialExtensions: Set<String> = ["crdownload", "download", "part", "partial", "tmp", "opdownload"]

    private(set) var known: Set<String> = []
    private(set) var pending: [String: Int64] = [:]
    private(set) var hasBaseline = false

    static func isPartial(_ name: String) -> Bool {
        if name.hasPrefix(".") { return true }
        let ext = (name as NSString).pathExtension.lowercased()
        return partialExtensions.contains(ext)
    }

    /// `listing` maps file names to sizes. Returns names that just finished.
    mutating func update(with listing: [String: Int64]) -> [String] {
        let names = Set(listing.keys.filter { !Self.isPartial($0) })
        guard hasBaseline else {
            known = names
            hasBaseline = true
            return []
        }
        var finished: [String] = []
        for name in names.subtracting(known).sorted() {
            let size = listing[name] ?? 0
            if let previous = pending[name], previous == size {
                finished.append(name)
                pending[name] = nil
                known.insert(name)
            } else {
                pending[name] = size
            }
        }
        // Forget files that were moved away, so a new one with that name is noticed again.
        known.formIntersection(names)
        pending = pending.filter { names.contains($0.key) }
        return finished
    }

    static func message(for names: [String]) -> String {
        if names.count == 1 { return "Your download finished: \(names[0])" }
        return "\(names.count) downloads finished!"
    }
}

// MARK: - Screenshots

enum ScreenshotTidy {
    /// Screenshots older than this are offered for tidying.
    static let minimumAge: TimeInterval = 24 * 3600
    /// She brings it up when at least this many have piled up.
    static let offerThreshold = 8
    static let folderName = "Screenshots"

    private static let prefixes = ["screenshot", "screen shot", "screen recording", "bildschirmfoto", "capture d"]
    private static let extensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "pdf", "mov", "mp4"]

    static func isScreenshot(_ name: String) -> Bool {
        let lower = name.lowercased()
        let ext = (lower as NSString).pathExtension
        return extensions.contains(ext) && prefixes.contains { lower.hasPrefix($0) }
    }

    /// The screenshots old enough to move, by name.
    static func candidates(_ files: [(name: String, modified: Date)], now: Date) -> [String] {
        files
            .filter { isScreenshot($0.name) && now.timeIntervalSince($0.modified) >= minimumAge }
            .map(\.name)
            .sorted()
    }

    /// A name that doesn't collide with what is already in the destination: "Shot.png", "Shot 2.png"…
    static func uniqueName(_ name: String, existing: Set<String>) -> String {
        guard existing.contains(name) else { return name }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var index = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            if !existing.contains(candidate) { return candidate }
            index += 1
        }
    }

    static func offer(count: Int) -> String {
        "Your desktop has \(count) old screenshots. Want me to tidy them? It's in my menu."
    }
}
