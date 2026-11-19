import AppKit

/// Native AppKit status item and menu controller.
///
/// Manages Cookie's presence in the macOS system menu bar:
/// - Robust `NSStatusItem` in `NSStatusBar.system` with light/dark adaptive icon (`isTemplate = true`)
/// - Text fallback if system symbol is ever unavailable
/// - Native `NSMenu` with hierarchical submenus for Feeding and Toys
/// - Standard application main menu (`NSApp.mainMenu`) so that the top-left menu bar
///   is also fully populated with Cookie controls when the app is active
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu()
    private unowned let environment: AppEnvironment
    private let store: CookieStore

    init(environment: AppEnvironment, store: CookieStore) {
        self.environment = environment
        self.store = store
        super.init()
        setupStatusItem()
        setupMainMenu()
    }

    // MARK: - Status Bar Item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let image = NSImage(named: "CookieMenuBar") {
                image.isTemplate = true
                image.accessibilityDescription = "Cookie"
                button.image = image
                button.imagePosition = .imageOnly
            } else {
                button.title = "Cookie"
            }
            button.toolTip = "Cookie"
            button.setAccessibilityLabel("Cookie")
        }

        statusMenu.delegate = self
        item.menu = statusMenu
        self.statusItem = item
        buildMenu(statusMenu)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        buildMenu(menu)
    }

    /// Creates a fresh, fully wired menu for contextual display (e.g., clicking on Cookie or Dock icon).
    func createMenu() -> NSMenu {
        let menu = NSMenu(title: "Cookie")
        buildMenu(menu)
        return menu
    }

    // MARK: - Menu Builder

    @discardableResult
    func buildMenu(_ menu: NSMenu) -> NSMenu {
        menu.removeAllItems()

        // 1. Profile display name header
        let titleItem = NSMenuItem(title: store.profile.displayName, action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(bondMenuItem())

        menu.addItem(.separator())

        // 2. Hide / Show Cookie
        if store.profile.isCompanionVisible {
            let hideItem = NSMenuItem(title: "Hide Cookie", action: #selector(toggleCompanionAction), keyEquivalent: "")
            hideItem.image = CookieArtwork.menuIcon("glyph-moon")
            hideItem.target = self
            menu.addItem(hideItem)
        } else {
            let showItem = NSMenuItem(title: "Show Cookie", action: #selector(toggleCompanionAction), keyEquivalent: "")
            showItem.image = CookieArtwork.menuIcon("glyph-moon")
            showItem.target = self
            menu.addItem(showItem)
        }

        menu.addItem(.separator())

        // 3. Pet Cookie
        let petItem = NSMenuItem(title: "Pet Cookie", action: #selector(petAction), keyEquivalent: "")
        petItem.image = CookieArtwork.menuIcon("glyph-paw")
        petItem.target = self
        menu.addItem(petItem)

        // 4. Play With Cookie
        let playItem = NSMenuItem(title: "Play", action: #selector(playAction), keyEquivalent: "")
        playItem.image = CookieArtwork.menuIcon("item-yarnBall")
        playItem.target = self
        menu.addItem(playItem)

        // 5. Emotes Entry
        let emotesItem = NSMenuItem(
            title: "Emotes…",
            action: #selector(openEmotesPickerAction),
            keyEquivalent: "e"
        )
        emotesItem.keyEquivalentModifierMask = [.command]
        emotesItem.image = CookieArtwork.menuIcon("emote-happy")
        emotesItem.target = self
        menu.addItem(emotesItem)

        menu.addItem(.separator())

        // 6. Feed Cookie Submenu
        let feedMenuItem = NSMenuItem(title: "Feed Cookie", action: nil, keyEquivalent: "")
        let feedSubmenu = NSMenu(title: "Feed Cookie")
        for food in FoodKind.allCases {
            let foodItem = NSMenuItem(
                title: food.displayName,
                action: #selector(feedAction(_:)),
                keyEquivalent: ""
            )
            foodItem.image = CookieArtwork.menuIcon(food.iconName)
            foodItem.target = self
            foodItem.representedObject = food
            feedSubmenu.addItem(foodItem)
        }
        feedMenuItem.image = CookieArtwork.menuIcon("item-food-fish")
        feedMenuItem.submenu = feedSubmenu
        menu.addItem(feedMenuItem)

        // 6. Toys Submenu
        let toysMenuItem = NSMenuItem(title: "Toys", action: nil, keyEquivalent: "")
        let toysSubmenu = NSMenu(title: "Toys")
        for toy in ToyKind.allCases {
            let toyItem = NSMenuItem(
                title: toy.displayName,
                action: #selector(offerToyAction(_:)),
                keyEquivalent: ""
            )
            toyItem.image = CookieArtwork.menuIcon(toy.iconName)
            toyItem.target = self
            toyItem.representedObject = toy
            lockIfNeeded(toyItem, .toy(toy), name: toy.displayName)
            toysSubmenu.addItem(toyItem)
        }
        if environment.hasActiveWorldItem {
            toysSubmenu.addItem(.separator())
            let clearItem = NSMenuItem(
                title: "Put Toys Away",
                action: #selector(clearWorldItemAction),
                keyEquivalent: ""
            )
            clearItem.image = CookieArtwork.menuIcon("item-box")
            clearItem.target = self
            toysSubmenu.addItem(clearItem)
        }
        toysMenuItem.image = CookieArtwork.menuIcon("item-ball")
        toysMenuItem.submenu = toysSubmenu
        menu.addItem(toysMenuItem)
        menu.addItem(cozyMenuItem())
        menu.addItem(focusMenuItem())
        menu.addItem(remindersMenuItem())
        menu.addItem(todoMenuItem())
        menu.addItem(notesMenuItem())
        if store.profile.settings.clipboardHistory {
            menu.addItem(clipboardMenuItem())
        }
        if store.profile.settings.askCookieEnabled {
            let ask = NSMenuItem(title: "Ask \(store.profile.displayName)…", action: #selector(askCookieAction), keyEquivalent: "")
            ask.image = NSImage(systemSymbolName: "bubble.left.and.text.bubble.right", accessibilityDescription: nil)
            ask.target = self
            menu.addItem(ask)
        }
        let quiet = environment.quietMode.isManuallyQuiet
        let quietItem = NSMenuItem(title: quiet ? "Quiet Mode: On" : "Quiet Mode", action: nil, keyEquivalent: "")
        quietItem.image = NSImage(systemSymbolName: quiet ? "speaker.slash.fill" : "speaker.slash", accessibilityDescription: nil)
        let quietMenu = NSMenu(title: "Quiet Mode")
        if quiet {
            let off = NSMenuItem(title: "Turn Off Quiet Mode", action: #selector(quietOffAction), keyEquivalent: "")
            off.target = self
            quietMenu.addItem(off)
        } else {
            for (title, minutes) in [("For 30 Minutes", 30), ("For 1 Hour", 60), ("For 2 Hours", 120), ("Until I Turn It Off", 0)] {
                let entry = NSMenuItem(title: title, action: #selector(quietOnAction(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = minutes
                quietMenu.addItem(entry)
            }
        }
        quietItem.submenu = quietMenu
        menu.addItem(quietItem)
        let tidyCount = environment.desk.tidyableScreenshotCount()
        if tidyCount > 0 {
            let tidy = NSMenuItem(title: "Tidy Up \(tidyCount) Screenshot\(tidyCount == 1 ? "" : "s")…", action: #selector(tidyScreenshotsAction), keyEquivalent: "")
            tidy.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
            tidy.target = self
            menu.addItem(tidy)
        }

        menu.addItem(.separator())

        // Photo Mode
        let photoItem = NSMenuItem(title: "Photo Mode…", action: #selector(photoModeAction), keyEquivalent: "")
        photoItem.image = CookieArtwork.menuIcon("emote-happy")
        photoItem.target = self
        menu.addItem(photoItem)

        // 7. Customize
        let customItem = NSMenuItem(title: "Customize Cookie…", action: #selector(customizeAction), keyEquivalent: "k")
        customItem.keyEquivalentModifierMask = .command
        customItem.image = CookieArtwork.menuIcon("glyph-palette")
        customItem.target = self
        menu.addItem(customItem)

        // 8. Settings
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(settingsAction), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        menu.addItem(settingsItem)

        // 9. Check for Updates
        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdatesAction), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(.separator())

        // 10. Quit
        let quitItem = NSMenuItem(title: "Quit Cookie", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Main Application Menu Bar (Top-Left)

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // 1. App menu (Cookie)
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Cookie")
        appMenu.addItem(NSMenuItem(title: "About Cookie", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(settingsAction), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        let customItem = NSMenuItem(title: "Customize Cookie…", action: #selector(customizeAction), keyEquivalent: "k")
        customItem.image = CookieArtwork.menuIcon("glyph-palette")
        customItem.target = self
        appMenu.addItem(customItem)
        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdatesAction), keyEquivalent: "")
        updateItem.target = self
        appMenu.addItem(updateItem)
        appMenu.addItem(.separator())
        let hideItem = NSMenuItem(title: "Hide Cookie", action: #selector(toggleCompanionAction), keyEquivalent: "h")
        hideItem.image = CookieArtwork.menuIcon("glyph-moon")
        hideItem.target = self
        appMenu.addItem(hideItem)
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Cookie", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 2. Care & Play menu
        let careMenuItem = NSMenuItem()
        let careMenu = NSMenu(title: "Care & Play")
        let petItem = NSMenuItem(title: "Pet Cookie", action: #selector(petAction), keyEquivalent: "p")
        petItem.image = CookieArtwork.menuIcon("glyph-paw")
        petItem.target = self
        careMenu.addItem(petItem)
        let playItem = NSMenuItem(title: "Play With Cookie", action: #selector(playAction), keyEquivalent: "l")
        playItem.image = CookieArtwork.menuIcon("item-yarnBall")
        playItem.target = self
        careMenu.addItem(playItem)
        careMenuItem.submenu = careMenu
        mainMenu.addItem(careMenuItem)

        // 3. Emotes menu
        let emotesMainMenu = NSMenuItem()
        let emotesMenu = NSMenu(title: "Emotes")
        let openPickerItem = NSMenuItem(title: "Open Emotes…", action: #selector(openEmotesPickerAction), keyEquivalent: "e")
        openPickerItem.keyEquivalentModifierMask = [.command]
        openPickerItem.image = CookieArtwork.menuIcon("emote-happy")
        openPickerItem.target = self
        emotesMenu.addItem(openPickerItem)
        emotesMenu.addItem(.separator())
        for emote in Emote.allEmotes {
            let item = NSMenuItem(
                title: emote.name,
                action: #selector(emoteAction(_:)),
                keyEquivalent: ""
            )
            item.image = CookieArtwork.menuIcon("emote-\(emote.id.rawValue)")
            item.target = self
            item.representedObject = emote
            emotesMenu.addItem(item)
        }
        emotesMainMenu.submenu = emotesMenu
        mainMenu.addItem(emotesMainMenu)

        // 4. Feed Cookie menu
        let feedMenuItem = NSMenuItem()
        let feedMenu = NSMenu(title: "Feed Cookie")
        for food in FoodKind.allCases {
            let foodItem = NSMenuItem(title: food.displayName, action: #selector(feedAction(_:)), keyEquivalent: "")
            foodItem.image = CookieArtwork.menuIcon(food.iconName)
            foodItem.target = self
            foodItem.representedObject = food
            feedMenu.addItem(foodItem)
        }
        feedMenuItem.submenu = feedMenu
        mainMenu.addItem(feedMenuItem)

        // 5. Toys menu
        let toysMenuItem = NSMenuItem()
        let toysMenu = NSMenu(title: "Toys")
        for toy in ToyKind.allCases {
            let toyItem = NSMenuItem(title: toy.displayName, action: #selector(offerToyAction(_:)), keyEquivalent: "")
            toyItem.image = CookieArtwork.menuIcon(toy.iconName)
            toyItem.target = self
            toyItem.representedObject = toy
            lockIfNeeded(toyItem, .toy(toy), name: toy.displayName)
            toysMenu.addItem(toyItem)
        }
        toysMenu.addItem(.separator())
        let clearItem = NSMenuItem(title: "Put Toys Away", action: #selector(clearWorldItemAction), keyEquivalent: "")
        clearItem.target = self
        toysMenu.addItem(clearItem)
        toysMenuItem.submenu = toysMenu
        mainMenu.addItem(toysMenuItem)

        // 6. Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(.separator())
        windowMenu.addItem(NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Friendship, focus and cozy corner

    /// Items still locked can't be chosen; the title says which level opens them.
    private func lockIfNeeded(_ item: NSMenuItem, _ unlock: BondItem, name: String) {
        guard !store.isUnlocked(unlock), let level = Bond.requiredLevel(for: unlock) else { return }
        item.title = "\(name) (\(level.name))"
        item.action = nil
        item.target = nil
        item.representedObject = nil
    }

    private func bondMenuItem() -> NSMenuItem {
        let progress = store.bondProgress
        let title: String
        if let next = progress.next {
            title = "\(progress.level.name) · \(store.bondPoints) of \(next.points)"
        } else {
            title = "\(progress.level.name) · fully bonded"
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = CookieArtwork.menuIcon("glyph-heart")
        item.isEnabled = false
        return item
    }

    private func focusMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Focus Session", action: nil, keyEquivalent: "")
        item.image = CookieArtwork.menuIcon("glyph-moon")
        let submenu = NSMenu(title: "Focus Session")
        let focus = environment.focus

        if focus.timer.isActive {
            let label = focus.isFocusing ? "Focusing: \(focus.timer.remainingLabel) left" : "On a break: \(focus.timer.remainingLabel) left"
            submenu.addItem(NSMenuItem(title: label, action: nil, keyEquivalent: ""))
            let stop = NSMenuItem(title: focus.isFocusing ? "Stop Session" : "Skip Break", action: #selector(stopFocusAction), keyEquivalent: "")
            stop.target = self
            submenu.addItem(stop)
        } else {
            var lengths = [15, 25, 50]
            let custom = store.profile.settings.focusMinutes
            if !lengths.contains(custom) { lengths.append(custom); lengths.sort() }
            for minutes in lengths {
                let entry = NSMenuItem(title: "Start \(minutes) Minutes", action: #selector(startFocusAction(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = minutes
                submenu.addItem(entry)
            }
        }
        item.submenu = submenu
        return item
    }

    private func remindersMenuItem() -> NSMenuItem {
        let reminders = environment.helpers.reminders
        let title = reminders.isEmpty ? "Reminders" : "Reminders (\(reminders.count))"
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "bell", accessibilityDescription: nil)
        let submenu = NSMenu(title: "Reminders")

        let new = NSMenuItem(title: "New Reminder…", action: #selector(newReminderAction), keyEquivalent: "")
        new.target = self
        submenu.addItem(new)

        let timer = NSMenuItem(title: "Quick Timer", action: nil, keyEquivalent: "")
        let timerMenu = NSMenu(title: "Quick Timer")
        for minutes in [1, 5, 10, 15, 30, 60] {
            let entry = NSMenuItem(title: CookieReminder.label(forMinutes: minutes), action: #selector(quickTimerAction(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = minutes
            timerMenu.addItem(entry)
        }
        timer.submenu = timerMenu
        submenu.addItem(timer)

        if !reminders.isEmpty {
            submenu.addItem(.separator())
            let now = Date()
            for reminder in reminders {
                let entry = NSMenuItem(title: "\(reminder.message) · \(reminder.remainingLabel(from: now))", action: nil, keyEquivalent: "")
                let cancelMenu = NSMenu()
                let cancel = NSMenuItem(title: "Cancel Reminder", action: #selector(cancelReminderAction(_:)), keyEquivalent: "")
                cancel.target = self
                cancel.representedObject = reminder.id
                cancelMenu.addItem(cancel)
                entry.submenu = cancelMenu
                submenu.addItem(entry)
            }
        }
        item.submenu = submenu
        return item
    }

    private func todoMenuItem() -> NSMenuItem {
        let todos = environment.desk.todos
        let open = todos.filter { !$0.isDone }.count
        let item = NSMenuItem(title: open == 0 ? "To-Do" : "To-Do (\(open))", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: nil)
        let submenu = NSMenu(title: "To-Do")

        let add = NSMenuItem(title: "Add Task…", action: #selector(addTodoAction), keyEquivalent: "")
        add.target = self
        submenu.addItem(add)

        if !todos.isEmpty {
            submenu.addItem(.separator())
            for todo in todos {
                let entry = NSMenuItem(title: todo.text, action: #selector(toggleTodoAction(_:)), keyEquivalent: "")
                entry.state = todo.isDone ? .on : .off
                entry.target = self
                entry.representedObject = todo.id
                entry.toolTip = todo.isDone ? "Click to mark as not done" : "Click to tick it off"
                submenu.addItem(entry)
            }
            if todos.contains(where: \.isDone) {
                submenu.addItem(.separator())
                let clear = NSMenuItem(title: "Clear Finished Tasks", action: #selector(clearTodosAction), keyEquivalent: "")
                clear.target = self
                submenu.addItem(clear)
            }
        }
        item.submenu = submenu
        return item
    }

    private func clipboardMenuItem() -> NSMenuItem {
        let items = environment.clipboard.history.items
        let item = NSMenuItem(title: "Clipboard", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        let submenu = NSMenu(title: "Clipboard")
        if items.isEmpty {
            let empty = NSMenuItem(title: "Nothing copied yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for text in items {
                let entry = NSMenuItem(title: ClipboardHistory.preview(text), action: #selector(copyBackAction(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = text
                entry.toolTip = "Copy this again"
                submenu.addItem(entry)
            }
            submenu.addItem(.separator())
            let clear = NSMenuItem(title: "Clear History", action: #selector(clearClipboardAction), keyEquivalent: "")
            clear.target = self
            submenu.addItem(clear)
        }
        item.submenu = submenu
        return item
    }

    private func notesMenuItem() -> NSMenuItem {
        let notes = store.profile.stickyNotes
        let item = NSMenuItem(title: notes.isEmpty ? "Sticky Notes" : "Sticky Notes (\(notes.count))", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: nil)
        let submenu = NSMenu(title: "Sticky Notes")
        let new = NSMenuItem(title: "New Note…", action: #selector(newNoteAction), keyEquivalent: "")
        new.target = self
        submenu.addItem(new)
        if !notes.isEmpty {
            let showing = store.profile.settings.showStickyNotes
            let toggle = NSMenuItem(title: showing ? "Hide Notes" : "Show Notes", action: #selector(toggleNotesAction), keyEquivalent: "")
            toggle.target = self
            submenu.addItem(toggle)
        }
        item.submenu = submenu
        return item
    }

    private func cozyMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Cozy Corner", action: nil, keyEquivalent: "")
        item.image = CookieArtwork.menuIcon("item-cozy-bed")
        let submenu = NSMenu(title: "Cozy Corner")
        for kind in CozyKind.allCases {
            let placed = store.profile.cozyItems.contains { $0.kind == kind }
            let entry = NSMenuItem(
                title: placed ? "Put Away \(kind.displayName)" : "Place \(kind.displayName)",
                action: placed ? #selector(removeCozyAction(_:)) : #selector(placeCozyAction(_:)),
                keyEquivalent: ""
            )
            entry.image = CookieArtwork.menuIcon(kind.iconName)
            entry.target = self
            entry.representedObject = kind
            if !placed { lockIfNeeded(entry, .cozy(kind), name: "Place \(kind.displayName)") }
            submenu.addItem(entry)
        }
        item.submenu = submenu
        return item
    }

    /// Shows the focus countdown beside the menu bar icon, or clears it.
    func updateStatusTitle(_ text: String?) {
        guard let button = statusItem?.button else { return }
        if let text {
            button.title = " \(text)"
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }

    // MARK: - Actions

    @objc private func photoModeAction() {
        environment.showPhotoMode()
    }

    @objc private func startFocusAction(_ sender: NSMenuItem) {
        environment.startFocus(minutes: sender.representedObject as? Int)
    }

    @objc private func stopFocusAction() {
        environment.stopFocus()
    }

    @objc private func askCookieAction() {
        environment.showAskCookie()
    }

    @objc private func quietOnAction(_ sender: NSMenuItem) {
        let minutes = sender.representedObject as? Int ?? 0
        environment.setQuiet(true, minutes: minutes > 0 ? minutes : nil)
    }

    @objc private func quietOffAction() {
        environment.setQuiet(false)
    }

    @objc private func copyBackAction(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        environment.clipboard.copyBack(text)
    }

    @objc private func clearClipboardAction() {
        environment.clipboard.clear()
    }

    @objc private func addTodoAction() {
        environment.showNewTodo()
    }

    @objc private func toggleTodoAction(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        environment.desk.toggleTodo(id: id)
    }

    @objc private func clearTodosAction() {
        environment.desk.clearCompletedTodos()
    }

    @objc private func newNoteAction() {
        environment.showNewStickyNote()
    }

    @objc private func toggleNotesAction() {
        store.profile.settings.showStickyNotes.toggle()
    }

    @objc private func tidyScreenshotsAction() {
        let count = environment.desk.tidyableScreenshotCount()
        let alert = NSAlert()
        alert.messageText = "Tidy up \(count) screenshot\(count == 1 ? "" : "s")?"
        alert.informativeText = "Screenshots older than a day will be moved into a folder called \"\(ScreenshotTidy.folderName)\" in the same place. Nothing is deleted."
        alert.addButton(withTitle: "Tidy Up")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        environment.desk.tidyScreenshots()
    }

    @objc private func newReminderAction() {
        environment.showNewReminder()
    }

    @objc private func quickTimerAction(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        environment.addReminder(text: "", minutes: minutes)
    }

    @objc private func cancelReminderAction(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        environment.cancelReminder(id: id)
    }

    @objc private func placeCozyAction(_ sender: NSMenuItem) {
        guard let kind = sender.representedObject as? CozyKind else { return }
        environment.placeCozy(kind)
    }

    @objc private func removeCozyAction(_ sender: NSMenuItem) {
        guard let kind = sender.representedObject as? CozyKind else { return }
        environment.removeCozy(kind)
    }

    @objc private func toggleCompanionAction() {
        environment.toggleCompanion()
    }

    @objc private func petAction() {
        environment.petCookie()
    }

    @objc private func emoteAction(_ sender: NSMenuItem) {
        guard let emote = sender.representedObject as? Emote else { return }
        environment.triggerEmote(emote)
    }

    @objc private func openEmotesPickerAction() {
        environment.showEmotePicker()
    }

    @objc private func feedAction(_ sender: NSMenuItem) {
        guard let food = sender.representedObject as? FoodKind else { return }
        environment.feedCookie(food: food)
    }

    @objc private func offerToyAction(_ sender: NSMenuItem) {
        guard let toy = sender.representedObject as? ToyKind else { return }
        environment.offerToy(toy)
    }

    @objc private func clearWorldItemAction() {
        environment.clearWorldItem()
    }

    @objc private func playAction() {
        environment.playWithCookie()
    }

    @objc private func customizeAction() {
        environment.showCustomization()
    }

    @objc private func settingsAction() {
        environment.showSettings()
    }

    @objc private func checkForUpdatesAction() {
        environment.checkForUpdates(userInitiated: true)
    }

    @objc private func quitAction() {
        environment.quit()
    }
}
