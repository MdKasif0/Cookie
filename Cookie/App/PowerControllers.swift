import AppKit
import Combine
import Security

// MARK: - Clipboard buddy

/// Watches the clipboard while the clipboard buddy is on. Text only, kept in memory only, and
/// anything a password manager marks as private is skipped.
@MainActor
final class ClipboardController: ObservableObject {
    @Published private(set) var history = ClipboardHistory()

    private let store: CookieStore
    private var timer: Timer?
    private var lastChangeCount: Int
    private var settingWatch: AnyCancellable?

    // Seams for tests.
    var pasteboard: NSPasteboard = .general

    init(store: CookieStore) {
        self.store = store
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        settingWatch = store.$profile
            .map(\.settings.clipboardHistory)
            .removeDuplicates()
            .sink { [weak self] on in self?.setWatching(on) }
    }

    func stop() {
        settingWatch = nil
        setWatching(false)
    }

    private func setWatching(_ on: Bool) {
        timer?.invalidate()
        timer = nil
        guard on else {
            // Turning it off forgets everything.
            history.clear()
            return
        }
        // Only what you copy from now on; nothing already on the clipboard.
        lastChangeCount = pasteboard.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer?.tolerance = 0.3
    }

    func poll() {
        guard store.profile.settings.clipboardHistory else { return }
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        let types = pasteboard.types?.map(\.rawValue) ?? []
        guard !ClipboardHistory.isPrivate(types: types),
              let text = pasteboard.string(forType: .string) else { return }
        history.add(text)
    }

    /// Puts an earlier copy back on the clipboard, ready to paste.
    func copyBack(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount
        history.add(text)
    }

    func clear() {
        history.clear()
    }
}

// MARK: - File drop zone

/// Drop files on Cookie and she offers to file them in your chosen folder, copy them there, or
/// zip them. Nothing is ever overwritten or deleted.
@MainActor
final class FileDropController: NSObject {
    private let store: CookieStore
    private let engine: CookieBehaviorEngine
    private let say: (String, TimeInterval) -> Void
    private let play: (SoundEffect) -> Void
    private var pending: [URL] = []

    init(store: CookieStore, engine: CookieBehaviorEngine,
         say: @escaping (String, TimeInterval) -> Void, play: @escaping (SoundEffect) -> Void) {
        self.store = store
        self.engine = engine
        self.say = say
        self.play = play
    }

    var acceptsDrops: Bool { store.profile.settings.fileDropEnabled }

    /// Called by Cookie's view when files land on her. Shows a small menu at the drop point.
    func handleDrop(_ urls: [URL], in view: NSView, at point: NSPoint) {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return }
        pending = files
        engine.react(.surprised)
        play(.chirp)

        let menu = NSMenu(title: "Dropped Files")
        let header = NSMenuItem(title: files.count == 1 ? files[0].lastPathComponent : "\(files.count) items", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        if let folder = store.profile.settings.dropFolder {
            add(menu, "Move to \(folder.lastPathComponent)", #selector(moveAction))
            add(menu, "Copy to \(folder.lastPathComponent)", #selector(copyAction))
        }
        add(menu, files.count == 1 ? "Zip It" : "Zip Them Together", #selector(zipAction))
        menu.addItem(.separator())
        add(menu, store.profile.settings.dropFolder == nil ? "Choose a Folder for Files…" : "Move to Another Folder…", #selector(chooseAction))
        menu.popUp(positioning: nil, at: point, in: view)
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    @objc private func moveAction() {
        guard let folder = store.profile.settings.dropFolder else { return }
        run(.move(to: folder))
    }

    @objc private func copyAction() {
        guard let folder = store.profile.settings.dropFolder else { return }
        run(.copy(to: folder))
    }

    @objc private func zipAction() { run(.zip) }

    @objc private func chooseAction() {
        let panel = NSOpenPanel()
        panel.title = "Choose Where Cookie Files Things"
        panel.prompt = "Move Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        store.profile.settings.dropFolderPath = folder.path
        run(.move(to: folder))
    }

    private func run(_ action: FileDropAction) {
        let files = pending
        pending = []
        Task.detached(priority: .userInitiated) {
            let done = Self.perform(action, on: files)
            await MainActor.run { [weak self] in self?.finish(done: done, of: files.count, action: action) }
        }
    }

    private func finish(done: Int, of total: Int, action: FileDropAction) {
        if done == total {
            engine.react(.happy)
            play(.happy)
            say(FileDrop.summary(count: total, action: action), 4)
        } else if done > 0 {
            say("I managed \(done) of \(total). The rest wouldn't budge.", 5)
        } else {
            engine.react(.annoyed)
            say("I couldn't do that. Check that Cookie can open that folder.", 5)
        }
    }

    /// Does the file work off the main thread. Returns how many files it handled.
    nonisolated static func perform(_ action: FileDropAction, on files: [URL]) -> Int {
        let fm = FileManager.default
        switch action {
        case .move(let folder), .copy(let folder):
            let copying = isCopy(action)
            var existing = Set((try? fm.contentsOfDirectory(atPath: folder.path)) ?? [])
            var done = 0
            for file in files {
                // Moving a file into the folder it's already in: nothing to do, and it's filed.
                if !copying, file.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL {
                    done += 1
                    continue
                }
                let target = FileDrop.destination(for: file, in: folder, existing: existing)
                do {
                    if copying {
                        try fm.copyItem(at: file, to: target)
                    } else {
                        try fm.moveItem(at: file, to: target)
                    }
                    existing.insert(target.lastPathComponent)
                    done += 1
                } catch {
                    continue
                }
            }
            return done
        case .zip:
            guard let first = files.first else { return 0 }
            let existing = Set((try? fm.contentsOfDirectory(atPath: first.deletingLastPathComponent().path)) ?? [])
            guard let zip = FileDrop.zipURL(for: files, existing: existing) else { return 0 }
            return zipFiles(files, to: zip) ? files.count : 0
        }
    }

    nonisolated private static func isCopy(_ action: FileDropAction) -> Bool {
        if case .copy = action { return true }
        return false
    }

    /// Uses the system's own `ditto`, the same tool Finder's Compress uses.
    nonisolated static func zipFiles(_ files: [URL], to zip: URL) -> Bool {
        let fm = FileManager.default
        if files.count == 1 {
            return runDitto(["-c", "-k", "--sequesterRsrc", "--keepParent", files[0].path, zip.path])
        }
        // Several files: gather them in a temporary folder so the zip holds them side by side.
        let staging = fm.temporaryDirectory.appendingPathComponent("cookie-zip-\(UUID().uuidString)", isDirectory: true)
        let inner = staging.appendingPathComponent(zip.deletingPathExtension().lastPathComponent, isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        do {
            try fm.createDirectory(at: inner, withIntermediateDirectories: true)
            var names: Set<String> = []
            for file in files {
                let name = ScreenshotTidy.uniqueName(file.lastPathComponent, existing: names)
                names.insert(name)
                try fm.copyItem(at: file, to: inner.appendingPathComponent(name))
            }
        } catch {
            return false
        }
        return runDitto(["-c", "-k", "--sequesterRsrc", "--keepParent", inner.path, zip.path])
    }

    nonisolated private static func runDitto(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

// MARK: - Ask Cookie

/// Stores the Claude API key in the login Keychain, never in Cookie's settings file.
enum APIKeyStore {
    private static let service = "com.cookie.mac.anthropic-api-key"
    private static let account = "default"

    static var hasKey: Bool { load() != nil }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        delete()
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "Cookie – Claude API key",
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecValueData as String: Data(trimmed.utf8),
        ]
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// The "Ask Cookie" chat. Each question goes to the Claude API with your own key; the
/// conversation lives only in this window's memory.
@MainActor
final class ChatController: ObservableObject {
    @Published private(set) var lines: [ChatLine] = []
    @Published private(set) var isThinking = false

    private let store: CookieStore
    private let engine: CookieBehaviorEngine
    /// Earlier turns exactly as sent and received.
    private var messages: [[String: Any]] = []
    private var task: Task<Void, Never>?

    /// Seam for tests: sends a request and returns the body and HTTP status.
    var send: (URLRequest) async throws -> (Data, Int) = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
    var apiKey: () -> String? = { APIKeyStore.load() }

    init(store: CookieStore, engine: CookieBehaviorEngine) {
        self.store = store
        self.engine = engine
    }

    var isReady: Bool { store.profile.settings.askCookieEnabled && apiKey() != nil }

    func ask(_ question: String) {
        let trimmed = String(question.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AskCookie.maximumQuestion))
        guard !trimmed.isEmpty, !isThinking else { return }
        guard store.profile.settings.askCookieEnabled else {
            lines.append(ChatLine(speaker: .notice, text: "Ask Cookie is turned off. Turn it on in Settings → Power Tools."))
            return
        }
        guard let key = apiKey() else {
            lines.append(ChatLine(speaker: .notice, text: "Add your Claude API key in Settings → Power Tools first."))
            return
        }
        if messages.count >= AskCookie.maximumMessages {
            messages = []
            lines.append(ChatLine(speaker: .notice, text: "That was a long chat! Starting a fresh one."))
        }

        lines.append(ChatLine(speaker: .you, text: trimmed))
        let outgoing = messages + [["role": "user", "content": trimmed]]
        isThinking = true

        var request = URLRequest(url: AskCookie.endpoint, timeoutInterval: 120)
        request.httpMethod = "POST"
        AskCookie.headers(apiKey: key).forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let system = AskCookie.systemPrompt(name: store.profile.displayName, personality: store.profile.personality.rawValue)
        request.httpBody = try? JSONSerialization.data(withJSONObject: AskCookie.requestBody(system: system, messages: outgoing))

        task = Task { [weak self] in
            let reply: AskCookie.Reply
            do {
                guard let self else { return }
                let (data, status) = try await self.send(request)
                reply = AskCookie.parse(data: data, status: status)
            } catch is CancellationError {
                return
            } catch {
                reply = .failed("Cookie couldn't reach Claude. Check your internet connection.")
            }
            self?.receive(reply, sent: outgoing)
        }
    }

    private func receive(_ reply: AskCookie.Reply, sent: [[String: Any]]) {
        isThinking = false
        switch reply {
        case .text(let text, let content):
            messages = sent + [["role": "assistant", "content": content.map(\.value)]]
            lines.append(ChatLine(speaker: .cookie, text: text))
            engine.react(.happy)
        case .declined:
            // The question isn't kept, so the conversation can carry on.
            lines.append(ChatLine(speaker: .notice, text: "Cookie can't help with that one. Try asking something else."))
        case .failed(let message):
            lines.append(ChatLine(speaker: .notice, text: message))
        }
    }

    func reset() {
        task?.cancel()
        task = nil
        isThinking = false
        messages = []
        lines = []
    }
}
