import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Break nudges, the focus guard and bedtime. Reminders live in Cookie's menu.
struct HelpersSettingsTab: View {
    @EnvironmentObject private var store: CookieStore
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        Form {
            Section {
                ForEach(SystemAlertKind.allCases) { kind in
                    Toggle(kind.displayName, isOn: systemBinding(kind))
                }
                Text("She checks every 20 seconds using public system information. No permission needed. Only a nearly flat battery interrupts a full-screen app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("System Watcher")
            }

            CalendarSettingsSection(calendar: environment.desk.calendar)

            Section {
                Toggle("Tell me when a download finishes", isOn: $store.profile.settings.downloadAlerts)
                    .accessibilityHint("Cookie watches your Downloads folder for new files")
                Toggle("Offer to tidy old screenshots", isOn: $store.profile.settings.screenshotTidyOffers)
                    .accessibilityHint("Cookie mentions it when old screenshots pile up, and adds a Tidy Up item to her menu")
                HStack {
                    Button("Tidy Up Now…") { confirmTidy() }
                        .disabled(!store.profile.settings.screenshotTidyOffers)
                    Button("Show Screenshots Folder") { environment.desk.revealScreenshotsFolder() }
                }
                Text("macOS will ask once whether Cookie may read your Downloads folder and Desktop. Tidying moves screenshots older than a day into a \"\(ScreenshotTidy.folderName)\" folder beside them. Nothing is deleted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Downloads & Screenshots")
            }

            Section {
                ForEach(BreakNudge.allCases) { nudge in
                    Toggle(isOn: nudgeBinding(nudge)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(nudge.displayName)
                            Text(nudge.settingsHint)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Text("Only time at the keyboard counts, and stepping away resets it. She waits during focus sessions, video calls and full-screen apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Break Nudges")
            }

            Section {
                Toggle("Cookie reacts when I open a distracting app", isOn: $store.profile.settings.focusGuardEnabled)
                    .accessibilityHint("During a focus session she comes over and gives you a look")
                if store.profile.settings.distractingApps.isEmpty {
                    Text("No apps yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.profile.settings.distractingApps) { app in
                        HStack {
                            AppIconView(bundleId: app.bundleId)
                            Text(app.name)
                            Spacer()
                            Button {
                                store.profile.settings.distractingApps.removeAll { $0.id == app.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove \(app.name)")
                        }
                    }
                }
                Button("Add App…", action: chooseApps)
                Text("Only works during a focus session. Cookie can see which app is in front, but never which website or document is open, so to count a site, add the whole browser.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Focus Guard")
            }

            Section {
                Toggle("Remind me when it's bedtime", isOn: $store.profile.settings.bedtimeEnabled)
                DatePicker("Bedtime", selection: bedtimeBinding, displayedComponents: .hourAndMinute)
                    .disabled(!store.profile.settings.bedtimeEnabled)
                Text("Once a night she yawns, suggests wrapping up, and curls up to sleep. She won't bring it up after 3 hours past bedtime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Bedtime")
            }
        }
        .formStyle(.grouped)
    }

    private func systemBinding(_ kind: SystemAlertKind) -> Binding<Bool> {
        Binding(
            get: { store.profile.settings.enabledSystemAlerts.contains(kind) },
            set: { store.profile.settings.setSystemAlert(kind, enabled: $0) }
        )
    }

    private func confirmTidy() {
        let count = environment.desk.tidyableScreenshotCount()
        let alert = NSAlert()
        if count == 0 {
            alert.messageText = "No old screenshots to tidy"
            alert.informativeText = "Screenshots older than a day will show up here."
            alert.runModal()
            return
        }
        alert.messageText = "Tidy up \(count) screenshot\(count == 1 ? "" : "s")?"
        alert.informativeText = "They'll be moved into a folder called \"\(ScreenshotTidy.folderName)\". Nothing is deleted."
        alert.addButton(withTitle: "Tidy Up")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { environment.desk.tidyScreenshots() }
    }

    private func nudgeBinding(_ nudge: BreakNudge) -> Binding<Bool> {
        Binding(
            get: { store.profile.settings.isNudgeEnabled(nudge) },
            set: { store.profile.settings.setNudge(nudge, enabled: $0) }
        )
    }

    private var bedtimeBinding: Binding<Date> {
        Binding(
            get: {
                let minutes = store.profile.settings.bedtimeMinutes
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                store.profile.settings.bedtimeMinutes = (parts.hour ?? 23) * 60 + (parts.minute ?? 0)
            }
        )
    }

    /// Picks apps from the Applications folder. Only the app's identifier and name are kept.
    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.title = "Choose Distracting Apps"
        panel.prompt = "Add"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        var apps = store.profile.settings.distractingApps
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                  id != Bundle.main.bundleIdentifier,
                  !apps.contains(where: { $0.bundleId == id }) else { continue }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            apps.append(DistractingApp(bundleId: id, name: name))
        }
        store.profile.settings.distractingApps = apps
    }
}

private struct AppIconView: View {
    let bundleId: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "app")
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
        }
    }
}

/// Calendar heads-ups. Turning them on is what asks macOS for calendar access.
private struct CalendarSettingsSection: View {
    @EnvironmentObject private var store: CookieStore
    @ObservedObject var calendar: CalendarSource
    @State private var asking = false

    var body: some View {
        Section {
            Toggle("Give me a heads-up before events", isOn: enabledBinding)
                .disabled(asking)
            Picker("How early", selection: $store.profile.settings.calendarLeadMinutes) {
                ForEach(CalendarHeadsUp.leadOptions, id: \.self) { minutes in
                    Text(minutes == 1 ? "1 minute before" : "\(minutes) minutes before").tag(minutes)
                }
            }
            .disabled(!store.profile.settings.calendarHeadsUp)
            if calendar.wasDenied {
                HStack {
                    Label("Cookie doesn't have calendar access.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Open Privacy Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                .font(.caption)
            }
            Text("She reads only the title and start time of upcoming events, from the calendars on this Mac. Nothing leaves your Mac. Heads-ups come over full-screen apps, like reminders.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Calendar")
        }
        .onAppear { calendar.refreshStatus() }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { store.profile.settings.calendarHeadsUp && calendar.hasAccess },
            set: { on in
                guard on else {
                    store.profile.settings.calendarHeadsUp = false
                    return
                }
                if calendar.hasAccess {
                    store.profile.settings.calendarHeadsUp = true
                    return
                }
                asking = true
                Task { @MainActor in
                    let granted = await calendar.requestAccess()
                    store.profile.settings.calendarHeadsUp = granted
                    asking = false
                }
            }
        )
    }
}
