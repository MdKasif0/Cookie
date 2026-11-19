import SwiftUI
import AppKit

/// Links and Shortcuts, the file drop zone, the clipboard buddy and Ask Cookie.
struct PowerToolsSettingsTab: View {
    @EnvironmentObject private var store: CookieStore
    @EnvironmentObject private var environment: AppEnvironment

    @State private var keyDraft = ""
    @State private var hasKey = APIKeyStore.hasKey
    @State private var keyMessage: String?

    var body: some View {
        Form {
            Section {
                Toggle("Allow cookie:// links and Shortcuts", isOn: $store.profile.settings.allowLinks)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Try these from Terminal, Raycast or a script:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Group {
                        Text("open \"cookie://say?text=Hello\"")
                        Text("open \"cookie://remind?minutes=20&text=Stretch\"")
                        Text("open \"cookie://focus/start?minutes=25\"")
                        Text("open \"cookie://quiet/on?minutes=60\"")
                    }
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    Text("Also: focus/stop, quiet/off, quiet/toggle, timer, todo/add, note, summon, show, hide, pet, emote?name=wave, ask. In the Shortcuts app, search for Cookie to find her actions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Links & Shortcuts")
            }

            Section {
                Toggle("Drop files on Cookie to file or zip them", isOn: $store.profile.settings.fileDropEnabled)
                HStack {
                    Text("Folder")
                    Spacer()
                    Text(store.profile.settings.dropFolder?.path(percentEncoded: false) ?? "Not chosen yet")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…", action: chooseFolder)
                }
                Text("Drag files onto Cookie and pick Move, Copy or Zip. Zips are made beside the original files. Nothing is overwritten or deleted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("File Drop Zone")
            }

            Section {
                Toggle("Remember my last \(ClipboardHistory.capacity) copies", isOn: $store.profile.settings.clipboardHistory)
                Text("Text only, kept in memory and never saved to disk: it's gone when Cookie quits or you turn this off. Anything a password manager marks as private is skipped. Find it under Clipboard in Cookie's menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Clipboard Buddy")
            }

            Section {
                Toggle("Chat with Cookie using Claude", isOn: $store.profile.settings.askCookieEnabled)
                HStack {
                    SecureField(hasKey ? "Key saved in your Keychain" : "Claude API key", text: $keyDraft)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Claude API key")
                    Button("Save") {
                        if APIKeyStore.save(keyDraft) {
                            keyMessage = "Saved in your Keychain."
                            keyDraft = ""
                        } else {
                            keyMessage = "Couldn't save that key."
                        }
                        hasKey = APIKeyStore.hasKey
                    }
                    .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    if hasKey {
                        Button("Remove", role: .destructive) {
                            APIKeyStore.delete()
                            hasKey = false
                            keyMessage = "Key removed."
                        }
                    }
                }
                if let keyMessage {
                    Text(keyMessage).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Open Chat") { environment.showAskCookie() }
                        .disabled(!store.profile.settings.askCookieEnabled || !hasKey)
                    Link("Get an API key", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                }
                Text("This is the one feature that goes online. Your questions and Cookie's name are sent to Anthropic's Claude API (model \(AskCookie.model)) and billed to your own API key. Nothing else on your Mac is sent, and the chat is forgotten when you close its window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Ask Cookie")
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Where Cookie Files Things"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.profile.settings.dropFolderPath = url.path
    }
}
