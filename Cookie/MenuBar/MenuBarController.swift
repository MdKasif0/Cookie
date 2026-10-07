import AppKit

/// Native AppKit status item and menu controller.
///
/// SwiftUI's `MenuBarExtra(style: .menu)` has documented limitations on macOS
/// with nested submenus and dynamic collections. Using a native `NSStatusItem`
/// and `NSMenu` guarantees standard macOS hierarchical submenus with disclosure
/// indicators for toys and feeding, dynamic menu updates, and zero dropped items.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private unowned let environment: AppEnvironment
    private let store: CookieStore

    init(environment: AppEnvironment, store: CookieStore) {
        self.environment = environment
        self.store = store
        super.init()
        setupStatusItem()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "cat.fill", accessibilityDescription: "Cookie")
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        self.statusItem = item
        buildMenu(menu)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        buildMenu(menu)
    }

    private func buildMenu(_ menu: NSMenu) {
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

        // 4. Feed Cookie Submenu
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

        // 5. Toys Submenu
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
                title: "Put Toys Away",
                action: #selector(clearWorldItemAction),
                keyEquivalent: ""
            )
            clearItem.target = self
            toysSubmenu.addItem(clearItem)
        }
        toysMenuItem.submenu = toysSubmenu
        menu.addItem(toysMenuItem)

        // 6. Play
        let playItem = NSMenuItem(title: "Play", action: #selector(playAction), keyEquivalent: "")
        playItem.target = self
        menu.addItem(playItem)

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

        menu.addItem(.separator())

        // 9. Quit
        let quitItem = NSMenuItem(title: "Quit Cookie", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func toggleCompanionAction() {
        environment.toggleCompanion()
    }

    @objc private func petAction() {
        environment.petCookie()
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
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    @objc private func quitAction() {
        environment.quit()
    }
}
