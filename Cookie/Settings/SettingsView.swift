import SwiftUI
import ServiceManagement

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettingsTab()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            SoundSettingsTab()
                .tabItem { Label("Sound", systemImage: "speaker.wave.2") }
            BehaviorSettingsTab()
                .tabItem { Label("Behavior", systemImage: "figure.walk") }
            PrivacySettingsTab()
                .tabItem { Label("Privacy", systemImage: "lock.shield") }
            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 540, height: 430)
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @EnvironmentObject private var store: CookieStore
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        Form {
            Section {
                Toggle("Launch Cookie at login", isOn: launchAtLogin)
                Toggle("Show Cookie on startup", isOn: $store.profile.settings.showOnStartup)
            } header: {
                Text("Startup")
            }
            Section {
                Toggle("Show Cookie on the desktop", isOn: $store.profile.isCompanionVisible)
                Toggle("Remember Cookie's position", isOn: $store.profile.settings.rememberPosition)
            } header: {
                Text("Desktop")
            }
            Section {
                Button("Customize Cookie…") {
                    environment.showCustomization()
                }
                Text("Fur, eyes, patterns, and accessories live in the customization window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { store.profile.settings.launchAtLogin },
            set: { environment.setLaunchAtLogin($0) }
        )
    }
}

// MARK: - Appearance

struct AppearanceSettingsTab: View {
    @EnvironmentObject private var store: CookieStore

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Size")
                    Slider(value: $store.profile.settings.cookieSize, in: 0.7...1.4)
                        .controlSize(.small)
                    Text(percent(store.profile.settings.cookieSize))
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
            } header: {
                Text("Cookie")
            } footer: {
                Text("Resizes Cookie on the desktop.")
            }
            Section {
                HStack {
                    Text("Intensity")
                    Slider(value: $store.profile.settings.animationIntensity, in: 0.5...1.5)
                        .controlSize(.small)
                    Text(percent(store.profile.settings.animationIntensity))
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
            } header: {
                Text("Animation")
            } footer: {
                Text("Higher values make Cookie's animations livelier.")
            }
            Section {
                Picker("Reduced motion", selection: $store.profile.settings.reducedMotionMode) {
                    ForEach(ReducedMotionMode.allCases) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                Text("When reduced, Cookie holds calm poses instead of moving — transitions still happen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Motion Accessibility")
            }
        }
        .formStyle(.grouped)
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

// MARK: - Sound

struct SoundSettingsTab: View {
    @EnvironmentObject private var store: CookieStore

    var body: some View {
        Form {
            Section {
                Toggle("Enable sounds", isOn: $store.profile.settings.soundEnabled)
                HStack {
                    Text("Master volume")
                    Slider(value: $store.profile.settings.masterVolume, in: 0...1)
                        .controlSize(.small)
                        .disabled(!store.profile.settings.soundEnabled)
                }
            } header: {
                Text("Sound")
            }
            Section {
                HStack {
                    Text("Meow volume")
                    Slider(value: $store.profile.settings.meowVolume, in: 0...1)
                        .controlSize(.small)
                        .disabled(!store.profile.settings.soundEnabled)
                }
                Toggle("Interaction sounds", isOn: $store.profile.settings.interactionSounds)
                    .disabled(!store.profile.settings.soundEnabled)
                Toggle("Purring & ambient sounds", isOn: $store.profile.settings.purringSounds)
                    .disabled(!store.profile.settings.soundEnabled)
            } header: {
                Text("Detail")
            } footer: {
                Text("Meow volume applies to meows and mild protests. Sounds are throttled so they never repeat in a rush.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Behavior

struct BehaviorSettingsTab: View {
    @EnvironmentObject private var store: CookieStore

    var body: some View {
        Form {
            Section {
                Picker("Activity level", selection: $store.profile.settings.activityLevel) {
                    ForEach(ActivityLevel.allCases) { level in
                        Text(level.displayName).tag(level.rawValue)
                    }
                }
            } header: {
                Text("Energy")
            } footer: {
                Text("Calm Cookie strolls less and rests more; lively Cookie wanders and plays often.")
            }
            Section {
                Toggle("Random interactions", isOn: $store.profile.settings.randomInteractions)
                Toggle("Cursor interaction", isOn: $store.profile.settings.cursorInteraction)
                Toggle("Window interaction", isOn: $store.profile.settings.windowInteraction)
            } header: {
                Text("Interactions")
            } footer: {
                Text("Random interactions let Cookie stretch, play, and wander on her own. Cursor interaction lets her glance at and occasionally follow the pointer.")
            }
            Section {
                Picker("Sleep behavior", selection: $store.profile.settings.sleepBehavior) {
                    ForEach(SleepBehavior.allCases) { behavior in
                        Text(behavior.displayName).tag(behavior.rawValue)
                    }
                }
            } header: {
                Text("Sleep")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Privacy

struct PrivacySettingsTab: View {
    var body: some View {
        Form {
            Section {
                Label("Everything works locally on your Mac.", systemImage: "desktopcomputer")
                Label("No account is required.", systemImage: "person")
                Label("Nothing syncs to the cloud.", systemImage: "icloud.slash")
                Label("No analytics or tracking.", systemImage: "chart.bar")
            } header: {
                Text("Cookie is private by design")
            } footer: {
                Text("All of Cookie's data — her name, customization, and memories — lives in a single file in Application Support. If analytics are ever added, they will be strictly opt-in.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

struct AboutSettingsTab: View {
    @EnvironmentObject private var store: CookieStore

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Name", value: store.profile.displayName)
                LabeledContent("Version", value: version)
                LabeledContent("Category", value: "Desktop Companion")
            } header: {
                Text("Cookie")
            }
            Section {
                Text("A tiny companion made with Swift, SwiftUI, and SpriteKit — designed to feel like a carefully crafted indie Mac app.")
                    .font(.callout)
            } header: {
                Text("Credits")
            }
            Section {
                Link("Cookie on GitHub", destination: URL(string: "https://github.com/MdKasif0/Cookie")!)
                Text("© 2026 Md Kasif Uddin. All rights reserved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Links & License")
            }
        }
        .formStyle(.grouped)
    }
}
