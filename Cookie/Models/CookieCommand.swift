import Foundation

/// Something you can ask Cookie to do from outside the app: a `cookie://` link (from Raycast,
/// a script, `open`, a browser bookmark) or a Shortcuts action. Both end up here.
///
///     cookie://say?text=Hello
///     cookie://remind?minutes=20&text=Call%20Mom
///     cookie://timer?minutes=5
///     cookie://focus/start?minutes=25      cookie://focus/stop
///     cookie://quiet/on?minutes=60         cookie://quiet/off      cookie://quiet/toggle
///     cookie://show   cookie://hide   cookie://summon   cookie://pet
///     cookie://emote?name=wave
///     cookie://todo/add?text=Water%20plants
///     cookie://note?text=Buy%20milk
///     cookie://ask
enum CookieCommand: Equatable {
    case say(String)
    case remind(text: String, minutes: Int)
    case startFocus(minutes: Int?)
    case stopFocus
    case quiet(on: Bool, minutes: Int?)
    case toggleQuiet
    case show
    case hide
    case summon
    case pet
    case emote(EmoteId)
    case addTodo(String)
    case addNote(String)
    case ask

    static let scheme = "cookie"
    /// Longest text a link may carry. Anything longer is cut, so a link can't flood the screen.
    static let maximumText = 280

    enum ParseError: Error, Equatable {
        case notACookieLink
        case unknown(String)
        case missing(String)
    }

    static func parse(_ url: URL) -> Result<CookieCommand, ParseError> {
        guard url.scheme?.lowercased() == scheme else { return .failure(.notACookieLink) }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            query[item.name.lowercased()] = item.value ?? ""
        }
        // cookie://focus/start has host "focus" and path "/start".
        let parts = ([url.host ?? ""] + url.pathComponents.filter { $0 != "/" })
            .map { $0.lowercased() }
            .filter { !$0.isEmpty }
        let route = parts.joined(separator: "/")

        func text(_ key: String = "text") -> String? {
            guard let raw = query[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
            return String(raw.prefix(maximumText))
        }
        func minutes(_ key: String = "minutes", in range: ClosedRange<Int> = 1...24 * 60) -> Int? {
            guard let raw = query[key] ?? query["min"], let value = Int(raw) else { return nil }
            return min(max(value, range.lowerBound), range.upperBound)
        }

        switch route {
        case "say":
            guard let message = text() else { return .failure(.missing("text")) }
            return .success(.say(message))
        case "remind", "reminder":
            guard let value = minutes() else { return .failure(.missing("minutes")) }
            return .success(.remind(text: text() ?? "", minutes: value))
        case "timer":
            guard let value = minutes() else { return .failure(.missing("minutes")) }
            return .success(.remind(text: "", minutes: value))
        case "focus", "focus/start":
            return .success(.startFocus(minutes: minutes(in: 5...180)))
        case "focus/stop":
            return .success(.stopFocus)
        case "quiet", "quiet/on":
            return .success(.quiet(on: true, minutes: minutes()))
        case "quiet/off":
            return .success(.quiet(on: false, minutes: nil))
        case "quiet/toggle":
            return .success(.toggleQuiet)
        case "show": return .success(.show)
        case "hide": return .success(.hide)
        case "summon", "come": return .success(.summon)
        case "pet": return .success(.pet)
        case "emote":
            guard let name = query["name"]?.lowercased() else { return .failure(.missing("name")) }
            guard let id = EmoteId(rawValue: name) else { return .failure(.unknown("emote \(name)")) }
            return .success(.emote(id))
        case "todo", "todo/add":
            guard let task = text() else { return .failure(.missing("text")) }
            return .success(.addTodo(task))
        case "note", "note/add":
            guard let note = text() else { return .failure(.missing("text")) }
            return .success(.addNote(note))
        case "ask", "chat":
            return .success(.ask)
        default:
            return .failure(.unknown(route.isEmpty ? "(empty)" : route))
        }
    }

    /// The link for this command, for Shortcuts to fall back on when Cookie isn't running yet.
    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        func set(_ host: String, _ items: [String: String] = [:]) {
            components.host = host
            components.queryItems = items.isEmpty ? nil : items.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        switch self {
        case .say(let text): set("say", ["text": text])
        case .remind(let text, let minutes):
            set("remind", text.isEmpty ? ["minutes": "\(minutes)"] : ["minutes": "\(minutes)", "text": text])
        case .startFocus(let minutes):
            set("focus", minutes.map { ["minutes": "\($0)"] } ?? [:])
            components.path = "/start"
        case .stopFocus: set("focus"); components.path = "/stop"
        case .quiet(let on, let minutes):
            set("quiet", minutes.map { ["minutes": "\($0)"] } ?? [:])
            components.path = on ? "/on" : "/off"
        case .toggleQuiet: set("quiet"); components.path = "/toggle"
        case .show: set("show")
        case .hide: set("hide")
        case .summon: set("summon")
        case .pet: set("pet")
        case .emote(let id): set("emote", ["name": id.rawValue])
        case .addTodo(let text): set("todo", ["text": text]); components.path = "/add"
        case .addNote(let text): set("note", ["text": text])
        case .ask: set("ask")
        }
        return components.url!
    }
}
