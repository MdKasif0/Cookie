import SwiftUI

struct StatsSettingsTab: View {
    @EnvironmentObject private var store: CookieStore
    @EnvironmentObject private var environment: AppEnvironment
    @State private var isResetConfirming = false

    var body: some View {
        Form {
            Section("Time Together") {
                LabeledContent("Days together", value: daysTogether)
                LabeledContent("First met", value: firstMetDate)
                LabeledContent("Launches", value: "\(store.statistics.launchCount)")
            }
            Section("Affection") {
                LabeledContent("Times petted", value: "\(store.statistics.petsReceived)")
            }
            Section {
                Button("Reset Cookie…", role: .destructive) {
                    isResetConfirming = true
                }
            } footer: {
                Text("Resets Cookie's name, look, statistics, and unlocks, and replays the welcome.")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Reset Cookie?", isPresented: $isResetConfirming, titleVisibility: .visible) {
            Button("Reset Cookie", role: .destructive) {
                environment.resetCookie()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Cookie forgets everything and the welcome plays again.")
        }
    }

    private var daysTogether: String {
        guard let first = store.statistics.firstLaunchedAt else { return "—" }
        let days = Calendar.current.dateComponents([.day], from: first, to: Date()).day ?? 0
        return "\(max(1, days + 1))"
    }

    private var firstMetDate: String {
        store.statistics.firstLaunchedAt?
            .formatted(date: .abbreviated, time: .omitted) ?? "—"
    }
}
