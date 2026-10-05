import SwiftUI

/// The first-run experience: a small, calm native window that introduces
/// Cookie, collects a name and personality, and launches the companion.
struct WelcomeView: View {
    @ObservedObject var model: WelcomeViewModel

    var body: some View {
        VStack(spacing: 0) {
            CharacterPreviewView()
                .frame(width: 150, height: 150)
                .padding(.top, 24)

            Text("Meet your new companion")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .padding(.top, 10)

            Text("A little cat who lives on your desktop — keeping you company while you work, blinking softly, and hopping over when you say hello.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.headline)
                    TextField("Cookie", text: $model.name)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Personality")
                        .font(.headline)
                    Picker("Personality", selection: $model.personality) {
                        ForEach(CookiePersonality.allCases) { personality in
                            Text(personality.displayName).tag(personality)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(model.personality.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 24)

            Spacer(minLength: 16)

            Button {
                model.continueTapped()
            } label: {
                Text("Bring \(model.resolvedName) Home")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 28)
        .frame(minWidth: 420, minHeight: 560)
        .background(Color("AppBackground").ignoresSafeArea())
    }
}
