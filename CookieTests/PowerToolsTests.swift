import XCTest
import AppKit
@testable import Cookie

final class CookieCommandTests: XCTestCase {
    private func parse(_ link: String) -> CookieCommand? {
        try? CookieCommand.parse(URL(string: link)!).get()
    }

    func testEveryRoute() {
        XCTAssertEqual(parse("cookie://say?text=Hello%20there"), .say("Hello there"))
        XCTAssertEqual(parse("cookie://remind?minutes=20&text=Call%20Mom"), .remind(text: "Call Mom", minutes: 20))
        XCTAssertEqual(parse("cookie://timer?minutes=5"), .remind(text: "", minutes: 5))
        XCTAssertEqual(parse("cookie://focus/start?minutes=50"), .startFocus(minutes: 50))
        XCTAssertEqual(parse("cookie://focus"), .startFocus(minutes: nil))
        XCTAssertEqual(parse("cookie://focus/stop"), .stopFocus)
        XCTAssertEqual(parse("cookie://quiet/on?minutes=60"), .quiet(on: true, minutes: 60))
        XCTAssertEqual(parse("cookie://quiet"), .quiet(on: true, minutes: nil))
        XCTAssertEqual(parse("cookie://quiet/off"), .quiet(on: false, minutes: nil))
        XCTAssertEqual(parse("cookie://quiet/toggle"), .toggleQuiet)
        XCTAssertEqual(parse("cookie://SHOW"), .show)
        XCTAssertEqual(parse("cookie://hide"), .hide)
        XCTAssertEqual(parse("cookie://summon"), .summon)
        XCTAssertEqual(parse("cookie://pet"), .pet)
        XCTAssertEqual(parse("cookie://emote?name=Wave"), .emote(.wave))
        XCTAssertEqual(parse("cookie://todo/add?text=Taxes"), .addTodo("Taxes"))
        XCTAssertEqual(parse("cookie://note?text=Milk"), .addNote("Milk"))
        XCTAssertEqual(parse("cookie://ask"), .ask)
    }

    func testBadLinksAreRejected() {
        XCTAssertEqual(CookieCommand.parse(URL(string: "https://example.com/say?text=hi")!), .failure(.notACookieLink))
        XCTAssertEqual(CookieCommand.parse(URL(string: "cookie://say")!), .failure(.missing("text")))
        XCTAssertEqual(CookieCommand.parse(URL(string: "cookie://say?text=%20%20")!), .failure(.missing("text")))
        XCTAssertEqual(CookieCommand.parse(URL(string: "cookie://remind?text=x")!), .failure(.missing("minutes")))
        XCTAssertEqual(CookieCommand.parse(URL(string: "cookie://emote?name=dance")!), .failure(.unknown("emote dance")))
        XCTAssertEqual(CookieCommand.parse(URL(string: "cookie://delete-everything")!), .failure(.unknown("delete-everything")))
    }

    func testValuesAreClampedAndTextIsCut() {
        XCTAssertEqual(parse("cookie://focus/start?minutes=1"), .startFocus(minutes: 5))
        XCTAssertEqual(parse("cookie://timer?minutes=99999"), .remind(text: "", minutes: 1440))
        let long = String(repeating: "a", count: 1000)
        XCTAssertEqual(parse("cookie://say?text=\(long)"), .say(String(repeating: "a", count: CookieCommand.maximumText)))
    }

    func testLinksRoundTrip() {
        let commands: [CookieCommand] = [
            .say("Hi & bye"), .remind(text: "Tea?", minutes: 3), .remind(text: "", minutes: 7),
            .startFocus(minutes: 25), .startFocus(minutes: nil), .stopFocus,
            .quiet(on: true, minutes: 30), .quiet(on: true, minutes: nil), .quiet(on: false, minutes: nil), .toggleQuiet,
            .show, .hide, .summon, .pet, .emote(.love), .addTodo("A/B test"), .addNote("50% off"), .ask,
        ]
        for command in commands {
            XCTAssertEqual(try? CookieCommand.parse(command.url).get(), command, command.url.absoluteString)
        }
    }
}

@MainActor
final class ManualQuietTests: XCTestCase {
    func testManualQuietLastsUntilItEndsAndRemindersCanPeekThrough() {
        let store = CookieStore(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("mquiet-\(UUID().uuidString).json"))
        let monitor = QuietModeMonitor(store: store)
        var clock = Date(timeIntervalSince1970: 9_000_000)
        monitor.now = { clock }
        monitor.windowSource = { [] }
        monitor.displaySource = { [] }

        monitor.setManualQuiet(true, minutes: 30)
        XCTAssertTrue(monitor.isQuiet)
        monitor.grantOverride(seconds: 20)
        XCTAssertFalse(monitor.isQuiet, "A reminder shows her briefly")
        clock = clock.addingTimeInterval(21)
        monitor.evaluate()
        XCTAssertTrue(monitor.isQuiet)
        clock = clock.addingTimeInterval(30 * 60)
        monitor.evaluate()
        XCTAssertFalse(monitor.isQuiet)
        XCTAssertNil(monitor.manualQuietUntil)

        monitor.setManualQuiet(true)
        clock = clock.addingTimeInterval(10 * 3600)
        monitor.evaluate()
        XCTAssertTrue(monitor.isQuiet, "No time limit means until turned off")
        monitor.setManualQuiet(false)
        XCTAssertFalse(monitor.isQuiet)
    }
}

final class ClipboardHistoryTests: XCTestCase {
    func testNewestFirstNoDuplicatesCapped() {
        var history = ClipboardHistory()
        XCTAssertFalse(history.add("   "))
        history.add("a")
        history.add("b")
        history.add("a")
        XCTAssertEqual(history.items, ["a", "b"])
        for i in 0..<20 { history.add("item \(i)") }
        XCTAssertEqual(history.items.count, ClipboardHistory.capacity)
        XCTAssertEqual(history.items.first, "item 19")
        XCTAssertFalse(history.add(String(repeating: "x", count: ClipboardHistory.maximumLength + 1)))
    }

    func testPrivateCopiesAreRecognised() {
        XCTAssertTrue(ClipboardHistory.isPrivate(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        XCTAssertFalse(ClipboardHistory.isPrivate(types: ["public.utf8-plain-text"]))
    }

    func testPreview() {
        XCTAssertEqual(ClipboardHistory.preview("  hello\n\n  world  "), "hello world")
        XCTAssertEqual(ClipboardHistory.preview(String(repeating: "a", count: 100), length: 10), "aaaaaaaaa…")
    }
}

@MainActor
final class ClipboardControllerTests: XCTestCase {
    func testOnlyWatchesWhileOnAndSkipsPasswords() {
        let store = CookieStore(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("clip-\(UUID().uuidString).json"))
        let board = NSPasteboard(name: NSPasteboard.Name("cookie-test-\(UUID().uuidString)"))
        let controller = ClipboardController(store: store)
        controller.pasteboard = board
        controller.start()
        defer { controller.stop(); board.releaseGlobally() }

        board.clearContents(); board.setString("before", forType: .string)
        controller.poll()
        XCTAssertTrue(controller.history.items.isEmpty, "Off by default")

        store.profile.settings.clipboardHistory = true
        board.clearContents(); board.setString("hello", forType: .string)
        controller.poll()
        XCTAssertEqual(controller.history.items, ["hello"])

        board.clearContents()
        board.declareTypes([.string, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")], owner: nil)
        board.setString("hunter2", forType: .string)
        controller.poll()
        XCTAssertEqual(controller.history.items, ["hello"], "Password manager copies are skipped")

        controller.copyBack("hello")
        XCTAssertEqual(board.string(forType: .string), "hello")

        store.profile.settings.clipboardHistory = false
        XCTAssertTrue(controller.history.items.isEmpty, "Turning it off forgets everything")
    }
}

final class FileDropTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("drop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("in"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("out"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func file(_ name: String, _ text: String = "x") throws -> URL {
        let url = folder.appendingPathComponent("in").appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    func testMovingNeverOverwrites() throws {
        let out = folder.appendingPathComponent("out")
        try Data("old".utf8).write(to: out.appendingPathComponent("a.txt"))
        let a = try file("a.txt", "new")
        let b = try file("b.txt")
        XCTAssertEqual(FileDropController.perform(.move(to: out), on: [a, b]), 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
        XCTAssertEqual(try String(contentsOf: out.appendingPathComponent("a.txt"), encoding: .utf8), "old")
        XCTAssertEqual(try String(contentsOf: out.appendingPathComponent("a 2.txt"), encoding: .utf8), "new")
        XCTAssertTrue(FileManager.default.fileExists(atPath: out.appendingPathComponent("b.txt").path))
    }

    func testCopyingKeepsTheOriginal() throws {
        let a = try file("a.txt")
        XCTAssertEqual(FileDropController.perform(.copy(to: folder.appendingPathComponent("out")), on: [a]), 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("out/a.txt").path))
    }

    func testZipOneOrSeveral() throws {
        let a = try file("report.pdf")
        let b = try file("notes.txt")
        XCTAssertEqual(FileDropController.perform(.zip, on: [a]), 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("in/report.zip").path))
        XCTAssertEqual(FileDropController.perform(.zip, on: [a, b]), 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("in/Archive.zip").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path), "Zipping leaves the originals")
        // Zipping again doesn't overwrite.
        XCTAssertEqual(FileDropController.perform(.zip, on: [a]), 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("in/report 2.zip").path))
    }

    func testSummaries() {
        XCTAssertEqual(FileDrop.summary(count: 1, action: .move(to: URL(fileURLWithPath: "/x/Work"))), "Filed it in Work!")
        XCTAssertEqual(FileDrop.summary(count: 3, action: .zip), "Zipped all 3 together!")
    }
}

final class AskCookieTests: XCTestCase {
    func testRequestShape() throws {
        let body = AskCookie.requestBody(system: "sys", messages: [["role": "user", "content": "hi"]])
        XCTAssertEqual(body["model"] as? String, "claude-opus-5-5")
        XCTAssertEqual((body["output_config"] as? [String: String])?["effort"], "low")
        XCTAssertEqual(body["fallbacks"] as? String, "default")
        XCTAssertNil(body["temperature"])
        XCTAssertNil(body["thinking"])
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
        let headers = AskCookie.headers(apiKey: "k")
        XCTAssertEqual(headers["anthropic-version"], "2026-10-21")
        XCTAssertEqual(headers["anthropic-beta"], "server-side-fallback-2026-07-01")
    }

    func testParsesTextAndKeepsEveryBlock() {
        let json = #"{"content":[{"type":"thinking","thinking":"","signature":"s"},{"type":"text","text":"Mrrp! "},{"type":"text","text":"Hello."}],"stop_reason":"end_turn"}"#
        guard case .text(let text, let content) = AskCookie.parse(data: Data(json.utf8), status: 200) else {
            return XCTFail("Expected text")
        }
        XCTAssertEqual(text, "Mrrp! Hello.")
        XCTAssertEqual(content.count, 3, "Thinking blocks are kept to send back unchanged")
    }

    func testRefusalsAndErrors() {
        XCTAssertEqual(AskCookie.parse(data: Data(#"{"content":[],"stop_reason":"refusal"}"#.utf8), status: 200), .declined)
        guard case .failed(let unauthorized) = AskCookie.parse(data: Data(#"{"type":"error","error":{"type":"authentication_error","message":"bad"}}"#.utf8), status: 401) else {
            return XCTFail()
        }
        XCTAssertTrue(unauthorized.contains("API key"))
        guard case .failed = AskCookie.parse(data: Data("nope".utf8), status: 502) else { return XCTFail() }
    }
}

@MainActor
final class ChatControllerTests: XCTestCase {
    func testOffByDefaultThenAsksWithHistory() async throws {
        let store = CookieStore(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("chat-\(UUID().uuidString).json"))
        let engine = CookieBehaviorEngine(store: store)
        let chat = ChatController(store: store, engine: engine)
        var sent: [[String: Any]] = []
        chat.apiKey = { "test-key" }
        chat.send = { request in
            sent.append(try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any])
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-key")
            return (Data(#"{"content":[{"type":"text","text":"Purr."}],"stop_reason":"end_turn"}"#.utf8), 200)
        }

        chat.ask("Hello")
        XCTAssertTrue(sent.isEmpty, "Off by default: nothing is sent")
        XCTAssertEqual(chat.lines.last?.speaker, .notice)

        store.profile.settings.askCookieEnabled = true
        chat.ask("Hello")
        try await waitUntil { !chat.isThinking }
        chat.ask("How are you?")
        try await waitUntil { !chat.isThinking }

        XCTAssertEqual(sent.count, 2)
        let second = sent[1]["messages"] as? [[String: Any]] ?? []
        XCTAssertEqual(second.map { $0["role"] as? String }, ["user", "assistant", "user"])
        XCTAssertEqual(chat.lines.filter { $0.speaker == .cookie }.map(\.text), ["Purr.", "Purr."])
        XCTAssertTrue((sent[0]["system"] as? String ?? "").contains(store.profile.displayName))

        chat.reset()
        XCTAssertTrue(chat.lines.isEmpty)
    }

    func testNoKeyNoRequest() {
        let store = CookieStore(storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("chat-\(UUID().uuidString).json"))
        store.profile.settings.askCookieEnabled = true
        let chat = ChatController(store: store, engine: CookieBehaviorEngine(store: store))
        chat.apiKey = { nil }
        var calls = 0
        chat.send = { _ in calls += 1; return (Data(), 200) }
        chat.ask("Hi")
        XCTAssertEqual(calls, 0)
        XCTAssertFalse(chat.isReady)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition())
    }
}
