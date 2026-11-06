import SwiftUI
import SpriteKit

/// The first-run experience: Cookie walks in, reacts as you name her, and acts out each
/// personality when you try it on.
struct WelcomeView: View {
    @ObservedObject var model: WelcomeViewModel
    @FocusState private var nameFocused: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            stage
            VStack(spacing: 18) {
                nameField
                personalityPicker
                Button {
                    model.continueTapped()
                } label: {
                    Text("Bring \(model.resolvedName) Home")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                }
                .cookieProminentButton()
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 22)
        }
        .frame(width: 480)
        .background(WindowBackdrop().ignoresSafeArea())
        .onAppear {
            model.begin()
            nameFocused = true
        }
    }

    private var stage: some View {
        ZStack(alignment: .top) {
            CookieStageColors.gradient

            Ellipse()
                .fill(CookieStageColors.floor)
                .frame(width: 180, height: 22)
                .blur(radius: 6)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 12)
                .opacity(model.hasArrived ? 1 : 0)
                .animation(.easeOut(duration: 0.3), value: model.hasArrived)

            SpriteView(scene: model.stage, options: [.allowsTransparency])

            if model.hasArrived {
                speechBubble
                    .padding(.top, 34)
                    .offset(x: 138)
                    .transition(.scale(scale: 0.7, anchor: .bottomLeading).combined(with: .opacity))
            }
        }
        .frame(height: 232)
        .clipped()
        .animation(.spring(duration: 0.4, bounce: 0.35), value: model.hasArrived)
    }

    private var speechBubble: some View {
        Text(model.greeting)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(maxWidth: 150)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .cookieGlass(cornerRadius: 14)
            .contentTransition(.interpolate)
            .animation(.easeOut(duration: 0.2), value: model.greeting)
            .accessibilityLabel("Cookie says \(model.greeting)")
    }

    private var nameField: some View {
        VStack(spacing: 6) {
            Text("What's her name?")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            TextField("Cookie", text: $model.name)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .focused($nameFocused)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .cookieGlass(cornerRadius: 12)
                .accessibilityLabel("Cookie's name")
        }
    }

    private var personalityPicker: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(CookiePersonality.allCases) { personality in
                    PersonalityCard(
                        personality: personality,
                        isSelected: model.personality == personality
                    ) {
                        model.personality = personality
                    }
                }
            }
            Text(model.personality.summary)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .top)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.15), value: model.personality)
        }
    }
}

/// A selectable card showing one personality as a small looping animation.
private struct PersonalityCard: View {
    let personality: CookiePersonality
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false
    @State private var frames: (images: [NSImage], fps: Double)?

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                animation
                    .frame(width: 72, height: 72)
                Text(personality.displayName)
                    .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(CardSurface(isSelected: isSelected))
        .scaleEffect(isSelected ? 1.03 : (isHovered ? 1.015 : 1))
        .animation(.spring(duration: 0.28, bounce: 0.4), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
        .onAppear {
            let sheet = personality.previewSheet
            frames = CookieArtwork.frames(category: sheet.category, sheet: sheet.name)
        }
        .accessibilityLabel(personality.displayName)
        .accessibilityHint(personality.summary)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var animation: some View {
        if let frames {
            TimelineView(.animation(minimumInterval: 1 / frames.fps, paused: MotionSettings.reduceMotion)) { context in
                let elapsed = context.date.timeIntervalSinceReferenceDate
                let index = Int(elapsed * frames.fps) % frames.images.count
                Image(nsImage: frames.images[MotionSettings.reduceMotion ? 0 : index])
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            }
        }
    }
}

private struct CardSurface: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        if isSelected {
            content
                .cookieSelectedGlass(cornerRadius: 14)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.cookieAccent, lineWidth: 1.5))
        } else {
            content.cookieGlass(cornerRadius: 14)
        }
    }
}
