import SwiftUI

struct GeneralSettingsTab: View {
    @EnvironmentObject private var store: CookieStore

    var body: some View {
        Form {
            Section("Companion") {
                LabeledContent("Name") {
                    TextField("Name", text: $store.profile.name)
                }
                Picker("Personality", selection: $store.profile.personality) {
                    ForEach(CookiePersonality.allCases) { personality in
                        Text(personality.displayName).tag(personality)
                    }
                }
                .pickerStyle(.radioGroup)
                Text(store.profile.personality.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Sound") {
                Toggle("Play sounds", isOn: $store.profile.soundEnabled)
                Slider(value: $store.profile.soundVolume, in: 0...1) {
                    Text("Volume")
                }
                .disabled(!store.profile.soundEnabled)
            }
        }
        .formStyle(.grouped)
    }
}
