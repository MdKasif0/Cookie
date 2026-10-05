import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettingsTab()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            StatsSettingsTab()
                .tabItem { Label("Statistics", systemImage: "heart.text.square") }
        }
        .frame(width: 520, height: 420)
    }
}
