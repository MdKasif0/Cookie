import SwiftUI

struct AppearanceSettingsTab: View {
    @EnvironmentObject private var store: CookieStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                CharacterPreviewView()
                    .frame(width: 140, height: 140)
                Spacer()
            }

            Text("Fur Palette")
                .font(.headline)
            VStack(spacing: 8) {
                ForEach(AppearanceCatalog.appearances) { appearance in
                    paletteRow(for: appearance)
                }
            }

            Divider()

            Text("Accessories")
                .font(.headline)
            ContentUnavailableView(
                "Coming soon",
                systemImage: "gift",
                description: Text("Hats, scarves, and little friends are on their way.")
            )
            .frame(maxHeight: .infinity)
        }
        .padding(24)
    }

    private func paletteRow(for appearance: CookieAppearance) -> some View {
        let palette = CharacterPalette.standard(for: appearance)
        let isSelected = store.profile.appearance == appearance
        return Button {
            store.profile.appearance = appearance
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(nsColor: palette.fur))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle().stroke(Color(nsColor: palette.stripe), lineWidth: 3)
                            .padding(5)
                    )
                Text(appearance.displayName)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
