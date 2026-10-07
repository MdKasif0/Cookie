import SwiftUI

/// Cookie's native menu bar menu: name header, companion controls,
/// care & play actions, and distinct sections for feeding and toys.
struct MenuBarContent: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var store: CookieStore

    var body: some View {
        Text(store.profile.displayName)
            .font(.system(size: 13, weight: .semibold, design: .rounded))

        Divider()

        if store.profile.isCompanionVisible {
            Button("Hide Cookie") { environment.toggleCompanion() }
        } else {
            Button("Show Cookie") { environment.toggleCompanion() }
        }

        Divider()

        Section("Care & Play") {
            Button("Pet Cookie") { environment.petCookie() }
            Button("Play") { environment.playWithCookie() }
        }

        Divider()

        Section("Feed Cookie") {
            Button("Fish 🐟") { environment.feedCookie(food: .fish) }
            Button("Milk 🥛") { environment.feedCookie(food: .milk) }
            Button("Chicken 🍗") { environment.feedCookie(food: .chicken) }
            Button("Cookie 🍪") { environment.feedCookie(food: .cookie) }
        }

        Divider()

        Section("Toys") {
            Button("Yarn Ball 🧶") { environment.offerToy(.yarnBall) }
            Button("Feather 🪶") { environment.offerToy(.feather) }
            Button("Toy Mouse 🐭") { environment.offerToy(.toyMouse) }
            Button("Fish Toy 🐟") { environment.offerToy(.fishToy) }
            Button("Ball 🎾") { environment.offerToy(.ball) }
            Button("Cardboard Box 📦") { environment.offerToy(.box) }
            if environment.hasActiveWorldItem {
                Button("Put Toys Away 🧹") { environment.clearWorldItem() }
            }
        }

        Divider()

        Button("Customize Cookie…") { environment.showCustomization() }
            .keyboardShortcut("k", modifiers: .command)

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit Cookie") { environment.quit() }
            .keyboardShortcut("q", modifiers: .command)
    }
}
