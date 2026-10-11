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
            StatsSettingsTab()
                .tabItem { Label("Stats", systemImage: "heart") }
            PrivacySettingsTab()
                .tabItem { Label("Privacy", systemImage: "lock.shield") }
            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 540, height: 440)
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
                    .accessibilityHint("Runs Cookie automatically whenever you log into macOS")
                Toggle("Show Cookie on startup", isOn: $store.profile.settings.showOnStartup)
                    .accessibilityHint("Displays Cookie on the desktop immediately upon application launch")
            } header: {
                Text("Startup")
            }
            Section {
                Toggle("Show Cookie on the desktop", isOn: $store.profile.isCompanionVisible)
                    .accessibilityHint("Shows or hides Cookie's floating desktop companion")
                Toggle("Remember Cookie's position", isOn: $store.profile.settings.rememberPosition)
                    .accessibilityHint("Restores Cookie to her last desktop position across launches")
            } header: {
                Text("Desktop")
            }
            Section {
                Button("Customize Cookie…") {
                    environment.showCustomization()
                }
                .accessibilityLabel("Open Customization Window")
                .accessibilityHint("Customize Cookie's fur, eye color, patterns, and accessories")

                Text("Fur, eyes, patterns, and accessories live in the customization window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Automatically check for updates", isOn: $store.profile.settings.automaticallyCheckForUpdates)
                    .accessibilityHint("Periodically checks for new releases of Cookie securely over HTTPS")

                Button("Check for Updates Now…") {
                    environment.checkForUpdates()
                }
                .accessibilityLabel("Check for Updates")
                .accessibilityHint("Checks GitHub feed for new Cookie releases")
            } header: {
                Text("Updates")
            } footer: {
                Text("Cookie checks for updates securely using Sparkle with cryptographic EdDSA verification. No personal data is sent.")
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
                        .accessibilityLabel("Cookie Size")
                        .accessibilityValue(percent(store.profile.settings.cookieSize))
                        .accessibilityHint("Adjusts Cookie's size on the desktop from 70% to 140%")
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
                        .accessibilityLabel("Animation Intensity")
                        .accessibilityValue(percent(store.profile.settings.animationIntensity))
                        .accessibilityHint("Higher values make Cookie's animations livelier")
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
                .accessibilityLabel("Reduced Motion Preference")
                .accessibilityHint("Configures whether movements and animations are calmed")

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
                    .accessibilityHint("Toggles all audio effects on or off")
                HStack {
                    Text("Master volume")
                    Slider(value: $store.profile.settings.masterVolume, in: 0...1)
                        .controlSize(.small)
                        .disabled(!store.profile.settings.soundEnabled)
                        .accessibilityLabel("Master Volume")
                        .accessibilityValue("\(Int(store.profile.settings.masterVolume * 100))%")
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
                        .accessibilityLabel("Meow Volume")
                        .accessibilityValue("\(Int(store.profile.settings.meowVolume * 100))%")
                }
                Toggle("Interaction sounds", isOn: $store.profile.settings.interactionSounds)
                    .disabled(!store.profile.settings.soundEnabled)
                    .accessibilityHint("Plays gentle sound effects during petting, feeding, and playing")
                Toggle("Purring & ambient sounds", isOn: $store.profile.settings.purringSounds)
                    .disabled(!store.profile.settings.soundEnabled)
                    .accessibilityHint("Plays soft purring sounds while resting or being stroked")
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
                .accessibilityLabel("Activity Level")
                .accessibilityHint("Controls how often Cookie walks around or rests")
            } header: {
                Text("Energy")
            } footer: {
                Text("Calm Cookie strolls less and rests more; lively Cookie wanders and plays often.")
            }
            Section {
                Toggle("Random interactions", isOn: $store.profile.settings.randomInteractions)
                    .accessibilityHint("Allows Cookie to autonomously stretch, play, and stroll")
                Toggle("Autonomous toys", isOn: $store.profile.settings.autonomousToys)
                    .accessibilityHint("Allows Cookie to occasionally explore toys on her own")
                Toggle("Window interaction", isOn: $store.profile.settings.windowInteraction)
                    .accessibilityHint("Reserved for future window perching behavior")
            } header: {
                Text("Interactions")
            } footer: {
                Text("Random interactions let Cookie stretch, play, and wander on her own. Autonomous toys let her occasionally explore a toy on the desk. All toys are optional.")
            }
            Section {
                Toggle("Enable cursor interactions", isOn: $store.profile.settings.cursorInteraction)
                    .accessibilityHint("Allows Cookie to notice and glance toward your cursor")
                Toggle("Enable playful following", isOn: $store.profile.settings.cursorFollowingEnabled)
                    .disabled(!store.profile.settings.cursorInteraction)
                    .accessibilityHint("Allows Cookie to curiously follow slow cursor movements")
                Toggle("Enable playful dodging", isOn: $store.profile.settings.cursorDodgingEnabled)
                    .disabled(!store.profile.settings.cursorInteraction)
                    .accessibilityHint("Allows Cookie to playfully step back when the cursor rushes in")
                Picker("Following intensity", selection: $store.profile.settings.cursorFollowingIntensity) {
                    ForEach(CursorFollowingIntensity.allCases) { intensity in
                        Text(intensity.displayName).tag(intensity.rawValue)
                    }
                }
                .disabled(!store.profile.settings.cursorInteraction || !store.profile.settings.cursorFollowingEnabled)
                .accessibilityLabel("Following Intensity")
                .accessibilityHint("Sets how quickly and closely Cookie follows the cursor")

                Button("Reset Cursor Settings to Defaults") {
                    store.profile.settings.resetCursorInteractionSettings()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .font(.callout)
            } header: {
                Text("Cursor Interaction")
            } footer: {
                Text("Cookie observes your cursor within an awareness radius and can curiously walk nearby or playfully step back. Rapid cursor movements are never chased.")
            }
            Section {
                Toggle("Enable Dock interactions", isOn: $store.profile.settings.dockInteraction)
                    .accessibilityHint("Allows Cookie to recognize and interact with the macOS Dock")
                Toggle("Enable autonomous Dock exploration", isOn: $store.profile.settings.autonomousDockExploration)
                    .disabled(!store.profile.settings.dockInteraction)
                    .accessibilityHint("Allows Cookie to occasionally and naturally stroll toward the Dock on her own")
                Picker("Dock exploration frequency", selection: $store.profile.settings.dockExplorationFrequency) {
                    ForEach(DockExplorationFrequency.allCases) { freq in
                        Text(freq.displayName).tag(freq.rawValue)
                    }
                }
                .disabled(!store.profile.settings.dockInteraction || !store.profile.settings.autonomousDockExploration)
                .accessibilityLabel("Dock Exploration Frequency")
                .accessibilityHint("Controls how often Cookie wanders to the Dock")

                Divider()

                Toggle("Enable window edge exploration", isOn: $store.profile.settings.windowInteraction)
                    .accessibilityHint("Allows Cookie to recognize and explore visible application window edges")
                Toggle("Enable vertical edge climbing", isOn: $store.profile.settings.windowVerticalClimbing)
                    .disabled(!store.profile.settings.windowInteraction)
                    .accessibilityHint("Allows Cookie to climb down vertical window borders")
                Picker("Window exploration frequency", selection: $store.profile.settings.windowExplorationFrequency) {
                    ForEach(WindowExplorationFrequency.allCases) { freq in
                        Text(freq.displayName).tag(freq.rawValue)
                    }
                }
                .disabled(!store.profile.settings.windowInteraction)
                .accessibilityLabel("Window Exploration Frequency")
                .accessibilityHint("Controls how often Cookie approaches and explores application window perimeters")

                Toggle("Enable window-to-window jumping", isOn: $store.profile.settings.windowJumpingEnabled)
                    .disabled(!store.profile.settings.windowInteraction)
                    .accessibilityHint("Allows Cookie to leap between adjacent windows and reachable surfaces")
                Picker("Jump frequency", selection: $store.profile.settings.jumpFrequency) {
                    ForEach(JumpFrequency.allCases) { freq in
                        Text(freq.displayName).tag(freq.rawValue)
                    }
                }
                .disabled(!store.profile.settings.windowInteraction || !store.profile.settings.windowJumpingEnabled)
                .accessibilityLabel("Jump Frequency")
                .accessibilityHint("Controls how often Cookie considers jumping between surfaces")
                Picker("Jump style", selection: $store.profile.settings.jumpStyle) {
                    ForEach(JumpStyle.allCases) { style in
                        Text(style.displayName).tag(style.rawValue)
                    }
                }
                .disabled(!store.profile.settings.windowInteraction || !store.profile.settings.windowJumpingEnabled)
                .accessibilityLabel("Jump Style")
                .accessibilityHint("Choose between gentle and playful trajectory arcs")

                Button("Reset Desktop Exploration to Defaults") {
                    store.profile.settings.resetDesktopExplorationSettings()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .font(.callout)
            } header: {
                Text("Desktop Exploration")
            } footer: {
                Text("Cookie detects visible window edges and the macOS Dock, approaching them naturally to stroll along safe top borders. Windows belonging to other applications are never controlled or altered.")
            }
            Section {
                Picker("Sleep behavior", selection: $store.profile.settings.sleepBehavior) {
                    ForEach(SleepBehavior.allCases) { behavior in
                        Text(behavior.displayName).tag(behavior.rawValue)
                    }
                }
                .accessibilityLabel("Sleep Schedule")
                .accessibilityHint("Sets normal, longer, or no autonomous sleep cycles")
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
    @EnvironmentObject private var environment: AppEnvironment

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (Build \(build))"
    }

    private var projectURL: URL {
        URL(string: "https://github.com/MdKasif0/Cookie") ?? URL(fileURLWithPath: "/")
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Name", value: store.profile.displayName)
                LabeledContent("Version", value: version)
                LabeledContent("Category", value: "Desktop Companion")

                Button("Check for Updates…") {
                    environment.checkForUpdates()
                }
                .accessibilityLabel("Check for Updates")
                .accessibilityHint("Checks for new Cookie updates")
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
                Link("Cookie on GitHub", destination: projectURL)
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
