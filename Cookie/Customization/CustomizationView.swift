import SwiftUI
import SpriteKit

// MARK: - Root

/// Cookie's character editor: category sidebar on the left, a large live
/// preview up top, and simple controls below. Every change applies
/// immediately — the store is the single source of truth.
struct CustomizationView: View {
    @EnvironmentObject private var store: CookieStore
    @State private var category: CustomizationCategory = .appearance

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Cookie")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 6)
                List(selection: $category) {
                    ForEach(CustomizationCategory.allCases) { item in
                        Label(item.title, systemImage: item.symbol)
                            .tag(item)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
            .frame(width: 176)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            VStack(spacing: 0) {
                preview
                Divider()
                pane
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .background(Color("AppBackground"))
        .frame(width: 620, height: 520)
    }

    // Large, quiet preview area on a soft warm backdrop.
    private var preview: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(.sRGB, red: 0.98, green: 0.95, blue: 0.89, opacity: 1),
                                Color(.sRGB, red: 0.95, green: 0.90, blue: 0.80, opacity: 1)
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                SpriteView(scene: previewScene, options: [.allowsTransparency])
                    .frame(width: 224, height: 224)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
            }
            .frame(width: 224, height: 224)
            .padding(.top, 20)

            Text(store.profile.displayName)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
    }

    @State private var previewScene = CookieScene(size: CGSize(width: 224, height: 224))

    @ViewBuilder
    private var pane: some View {
        ScrollView {
            Group {
                switch category {
                case .appearance: AppearancePane()
                case .accessories: AccessoriesPane()
                case .personality: PersonalityPane()
                case .name: NamePane()
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

enum CustomizationCategory: String, CaseIterable, Identifiable {
    case appearance
    case accessories
    case personality
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appearance: return "Appearance"
        case .accessories: return "Accessories"
        case .personality: return "Personality"
        case .name: return "Name"
        }
    }

    var symbol: String {
        switch self {
        case .appearance: return "paintpalette"
        case .accessories: return "crown"
        case .personality: return "face.smiling"
        case .name: return "character.cursor.ibeam"
        }
    }
}

// MARK: - Appearance

struct AppearancePane: View {
    @EnvironmentObject private var store: CookieStore

    private var config: CookieAppearanceConfig {
        store.profile.customization
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Fur Color") {
                SwatchRow(
                    options: FurColor.allCases,
                    selection: config.furColor,
                    swatch: { $0.swatch },
                    title: { $0.displayName }
                ) { store.profile.customization.furColor = $0 }
            }

            section("Fur Pattern") {
                Picker("Fur Pattern", selection: bind(\.furPattern)) {
                    ForEach(FurPattern.allCases) { pattern in
                        Text(pattern.displayName).tag(pattern)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            section("Eyes") {
                HStack {
                    Text("Color")
                        .frame(width: 72, alignment: .leading)
                    SwatchRow(
                        options: EyeColor.allCases,
                        selection: config.eyeColor,
                        swatch: { $0.swatch },
                        title: { $0.displayName }
                    ) { store.profile.customization.eyeColor = $0 }
                }
                HStack {
                    Text("Style")
                        .frame(width: 72, alignment: .leading)
                    Picker("Eye Style", selection: bind(\.eyeStyle)) {
                        ForEach(EyeStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
            }

            section("Body") {
                Picker("Body Variation", selection: bind(\.bodyVariation)) {
                    ForEach(BodyVariation.allCases) { variation in
                        Text(variation.displayName).tag(variation)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            section("Ears & Tail") {
                HStack {
                    Text("Ears")
                        .frame(width: 72, alignment: .leading)
                    Picker("Ear Variation", selection: bind(\.earVariation)) {
                        ForEach(EarVariation.allCases) { variation in
                            Text(variation.displayName).tag(variation)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
                HStack {
                    Text("Tail")
                        .frame(width: 72, alignment: .leading)
                    Picker("Tail Variation", selection: bind(\.tailVariation)) {
                        ForEach(TailVariation.allCases) { variation in
                            Text(variation.displayName).tag(variation)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
                Text("Ear and tail shapes apply when layered artwork provides those pieces.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Spacer()
                Button("Revert Appearance") {
                    store.profile.customization = CookieAppearanceConfig()
                }
            }
        }
    }

    private func bind<T: Equatable>(_ keyPath: WritableKeyPath<CookieAppearanceConfig, T>)
        -> Binding<T> {
        Binding(
            get: { store.profile.customization[keyPath: keyPath] },
            set: { store.profile.customization[keyPath: keyPath] = $0 }
        )
    }
}

// MARK: - Accessories

struct AccessoriesPane: View {
    @EnvironmentObject private var store: CookieStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Accessories layer over Cookie's artwork — position and scale them so they sit just right.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(AccessoryKind.allCases) { kind in
                accessoryRow(kind)
                if kind != AccessoryKind.allCases.last {
                    Divider()
                }
            }

            HStack {
                Spacer()
                Button("Remove All") {
                    for index in store.profile.customization.accessories.indices {
                        store.profile.customization.accessories[index].isEnabled = false
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private func accessoryRow(_ kind: AccessoryKind) -> some View {
        let binding = accessoryBinding(kind)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(kind.displayName, isOn: binding.isEnabled)
                if kind.isSeasonal {
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: kind.theme.icon)
                        Text(kind.theme.displayName)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }
            }
            if binding.isEnabled.wrappedValue {
                HStack(spacing: 12) {
                    Text("Size")
                        .frame(width: 44, alignment: .leading)
                    Slider(value: binding.scale, in: 0.75...1.3)
                        .controlSize(.small)
                        .accessibilityLabel("\(kind.displayName) Size")
                    Text("Height")
                        .frame(width: 44, alignment: .trailing)
                    Slider(value: binding.offsetY, in: -0.08...0.08)
                        .controlSize(.small)
                        .accessibilityLabel("\(kind.displayName) Vertical Position")
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func accessoryBinding(_ kind: AccessoryKind) -> (
        isEnabled: Binding<Bool>, scale: Binding<Double>, offsetY: Binding<Double>
    ) {
        let config = Binding<AccessoryConfig>(
            get: { store.profile.customization.accessory(for: kind) },
            set: { store.profile.customization.setAccessory($0) }
        )
        return (
            Binding(get: { config.wrappedValue.isEnabled }, set: { config.wrappedValue.isEnabled = $0 }),
            Binding(get: { Double(config.wrappedValue.scale) }, set: { config.wrappedValue.scale = CGFloat($0) }),
            Binding(get: { Double(config.wrappedValue.offsetY) }, set: { config.wrappedValue.offsetY = CGFloat($0) })
        )
    }
}

// MARK: - Personality

struct PersonalityPane: View {
    @EnvironmentObject private var store: CookieStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Personality shapes how Cookie behaves — her moods, strolls, and naps. It never changes who she is.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Personality", selection: $store.profile.personality) {
                ForEach(CookiePersonality.allCases) { personality in
                    HStack {
                        Text(personality.displayName)
                        Text(personality.summary).font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(personality)
                }
            }
            .pickerStyle(.radioGroup)

            Text(selectedSummary)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var selectedSummary: String {
        store.profile.personality.summary
    }
}

// MARK: - Name

struct NamePane: View {
    @EnvironmentObject private var store: CookieStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Cookie answers to whatever you call her — the name shows in the menu bar and here.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text("Name")
                TextField("Cookie", text: $store.profile.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
            }
            Text("She will go by \(store.profile.displayName).")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Reset to Cookie") {
                store.profile.name = "Cookie"
            }
        }
    }
}

// MARK: - Shared bits

/// A row of round color swatches; the selected one gets a ring.
struct SwatchRow<Option: Identifiable & Equatable>: View {
    let options: [Option]
    let selection: Option
    let swatch: (Option) -> CGColor
    let title: (Option) -> String
    let onSelect: (Option) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(options) { option in
                Button {
                    onSelect(option)
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(cgColor: swatch(option)))
                            .frame(width: 26, height: 26)
                            .overlay(
                                Circle().stroke(
                                    Color.primary.opacity(0.15),
                                    lineWidth: 1
                                )
                            )
                        if option == selection {
                            Circle()
                                .stroke(Color.primary.opacity(0.7), lineWidth: 2)
                                .frame(width: 32, height: 32)
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(
                                    Color(nsColor: .alternateSelectedControlTextColor)
                                )
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(title(option))
            }
        }
    }
}

private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        Text(title)
            .font(.headline)
        content()
    }
}
