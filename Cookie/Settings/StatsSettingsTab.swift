import SwiftUI

struct StatsSettingsTab: View {
    @EnvironmentObject private var store: CookieStore
    @EnvironmentObject private var environment: AppEnvironment
    @State private var isResetConfirming = false

    var body: some View {
        Form {
            friendshipSection
            Section("Time Together") {
                LabeledContent("Days together", value: daysTogether)
                LabeledContent("First met", value: firstMetDate)
                LabeledContent("Launches", value: "\(store.statistics.launchCount)")
            }
            Section("Affection") {
                LabeledContent("Times petted", value: "\(store.statistics.petsReceived)")
                LabeledContent("Affection", value: "\(store.statistics.affection)")
            }
            Section("Focus") {
                LabeledContent("Sessions completed", value: "\(store.statistics.focusSessions)")
                LabeledContent("Minutes focused", value: "\(store.statistics.focusMinutes)")
            }
            Section("Care & Play") {
                LabeledContent("Total interactions", value: "\(store.statistics.totalInteractions)")
                LabeledContent("Treats given", value: "\(store.statistics.treatsGiven)")
                LabeledContent("Toys played with", value: "\(store.statistics.toysPlayedWith)")
                LabeledContent("Cardboard box visits", value: "\(store.statistics.boxVisits)")
                if let favorite = store.statistics.favoriteToy {
                    LabeledContent("Favorite toy", value: favorite.displayName)
                }
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

    @ViewBuilder
    private var friendshipSection: some View {
        let progress = store.bondProgress
        Section("Friendship") {
            LabeledContent("Bond", value: progress.level.name)
            ProgressView(value: progress.fraction)
                .accessibilityLabel("Progress to the next friendship level")
            if let next = progress.next {
                Text("\(progress.pointsToNext) more points to reach \(next.name). Pets, treats, play and focus sessions all count, and so does each new day together.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("You and Cookie are as close as can be.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        Section("Unlocks") {
            ForEach(Bond.levels.dropFirst()) { level in
                let reached = store.bondPoints >= level.points
                VStack(alignment: .leading, spacing: 2) {
                    Label("\(level.name) · \(level.points) points", systemImage: reached ? "checkmark.circle.fill" : "lock.fill")
                        .foregroundStyle(reached ? Color.primary : Color.secondary)
                    Text(level.unlocks.map(\.displayName).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
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
