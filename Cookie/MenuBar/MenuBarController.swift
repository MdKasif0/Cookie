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
            if let image = NSImage(systemSymbolName: "cat.fill", accessibilityDescription: "Cookie") {
                image.isTemplate = true
                button.image = image
                button.imagePosition = .imageOnly
            } else {
                button.title = "🐱 Cookie"
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

        menu.addItem(.separator())

        // 2. Hide / Show Cookie
        if store.profile.isCompanionVisible {
            let hideItem = NSMenuItem(title: "Hide Cookie", action: #selector(toggleCompanionAction), keyEquivalent: "")
            hideItem.target = self
            menu.addItem(hideItem)
        } else {
            let showItem = NSMenuItem(title: "Show Cookie", action: #selector(toggleCompanionAction), keyEquivalent: "")
            showItem.target = self
            menu.addItem(showItem)
        }

        menu.addItem(.separator())

        // 3. Pet Cookie
        let petItem = NSMenuItem(title: "Pet Cookie", action: #selector(petAction), keyEquivalent: "")
        petItem.target = self
        menu.addItem(petItem)

        // 4. Play With Cookie
        let playItem = NSMenuItem(title: "Play", action: #selector(playAction), keyEquivalent: "")
        playItem.target = self
        menu.addItem(playItem)

        // 5. Emotes Entry
        let emotesItem = NSMenuItem(
            title: "Emotes…",
            action: #selector(openEmotesPickerAction),
            keyEquivalent: "e"
        )
        emotesItem.keyEquivalentModifierMask = [.command]
        emotesItem.target = self
        menu.addItem(emotesItem)

        menu.addItem(.separator())

        // 6. Feed Cookie Submenu
        let feedMenuItem = NSMenuItem(title: "Feed Cookie", action: nil, keyEquivalent: "")
        let feedSubmenu = NSMenu(title: "Feed Cookie")
        for food in FoodKind.allCases {
            let foodItem = NSMenuItem(
                title: "\(food.displayName) \(food.emoji)",
                action: #selector(feedAction(_:)),
                keyEquivalent: ""
            )
            foodItem.target = self
            foodItem.representedObject = food
            feedSubmenu.addItem(foodItem)
        }
        feedMenuItem.submenu = feedSubmenu
        menu.addItem(feedMenuItem)

        // 6. Toys Submenu
        let toysMenuItem = NSMenuItem(title: "Toys", action: nil, keyEquivalent: "")
        let toysSubmenu = NSMenu(title: "Toys")
        for toy in ToyKind.allCases {
            let toyItem = NSMenuItem(
                title: "\(toy.displayName) \(toy.emoji)",
                action: #selector(offerToyAction(_:)),
                keyEquivalent: ""
            )
            toyItem.target = self
            toyItem.representedObject = toy
            toysSubmenu.addItem(toyItem)
        }
        if environment.hasActiveWorldItem {
            toysSubmenu.addItem(.separator())
            let clearItem = NSMenuItem(
                title: "Put Toys Away 🧹",
                action: #selector(clearWorldItemAction),
                keyEquivalent: ""
            )
            clearItem.target = self
            toysSubmenu.addItem(clearItem)
        }
        toysMenuItem.submenu = toysSubmenu
        menu.addItem(toysMenuItem)

        menu.addItem(.separator())

        // 7. Customize
        let customItem = NSMenuItem(title: "Customize Cookie…", action: #selector(customizeAction), keyEquivalent: "k")
        customItem.keyEquivalentModifierMask = .command
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
        customItem.target = self
        appMenu.addItem(customItem)
        appMenu.addItem(.separator())
        let hideItem = NSMenuItem(title: "Hide Cookie", action: #selector(toggleCompanionAction), keyEquivalent: "h")
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
        petItem.target = self
        careMenu.addItem(petItem)
        let playItem = NSMenuItem(title: "Play With Cookie", action: #selector(playAction), keyEquivalent: "l")
        playItem.target = self
        careMenu.addItem(playItem)
        careMenuItem.submenu = careMenu
        mainMenu.addItem(careMenuItem)

        // 3. Emotes menu
        let emotesMainMenu = NSMenuItem()
        let emotesMenu = NSMenu(title: "Emotes")
        let openPickerItem = NSMenuItem(title: "Open Emotes…", action: #selector(openEmotesPickerAction), keyEquivalent: "e")
        openPickerItem.keyEquivalentModifierMask = [.command]
        openPickerItem.target = self
        emotesMenu.addItem(openPickerItem)
        emotesMenu.addItem(.separator())
        for emote in Emote.allEmotes {
            let item = NSMenuItem(
                title: "\(emote.name) \(emote.emoji)",
                action: #selector(emoteAction(_:)),
                keyEquivalent: ""
            )
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
            let foodItem = NSMenuItem(title: "\(food.displayName) \(food.emoji)", action: #selector(feedAction(_:)), keyEquivalent: "")
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
            let toyItem = NSMenuItem(title: "\(toy.displayName) \(toy.emoji)", action: #selector(offerToyAction(_:)), keyEquivalent: "")
            toyItem.target = self
            toyItem.representedObject = toy
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

    // MARK: - Actions

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

    private static func emoteEmoji(for id: EmoteId) -> String {
        id.emoji
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

    @objc private func quitAction() {
        environment.quit()
    }
}
