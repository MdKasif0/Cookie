import SwiftUI

/// Warm, elegant color palette strictly adhering to Cookie's design aesthetic.
/// Zero purple, zero blue.
private enum EmoteColors {
    static let warmWhite = Color(nsColor: NSColor(calibratedRed: 0.99, green: 0.98, blue: 0.96, alpha: 1.0))
    static let cream = Color(nsColor: NSColor(calibratedRed: 0.97, green: 0.95, blue: 0.91, alpha: 1.0))
    static let ivory = Color(nsColor: NSColor(calibratedRed: 0.95, green: 0.92, blue: 0.87, alpha: 1.0))
    static let softBeige = Color(nsColor: NSColor(calibratedRed: 0.92, green: 0.88, blue: 0.82, alpha: 1.0))
    static let warmPeach = Color(nsColor: NSColor(calibratedRed: 0.95, green: 0.86, blue: 0.79, alpha: 1.0))
    static let warmPeachHighlight = Color(nsColor: NSColor(calibratedRed: 0.98, green: 0.91, blue: 0.85, alpha: 1.0))
    static let mutedSage = Color(nsColor: NSColor(calibratedRed: 0.74, green: 0.78, blue: 0.72, alpha: 1.0))
    static let softOrange = Color(nsColor: NSColor(calibratedRed: 0.91, green: 0.61, blue: 0.41, alpha: 1.0))
    static let softOrangePressed = Color(nsColor: NSColor(calibratedRed: 0.85, green: 0.55, blue: 0.36, alpha: 1.0))
    static let warmBrown = Color(nsColor: NSColor(calibratedRed: 0.44, green: 0.31, blue: 0.22, alpha: 1.0))
    static let darkCharcoal = Color(nsColor: NSColor(calibratedRed: 0.22, green: 0.20, blue: 0.19, alpha: 1.0))
    static let neutralGray = Color(nsColor: NSColor(calibratedRed: 0.54, green: 0.51, blue: 0.48, alpha: 1.0))
    static let subtleBorder = Color(nsColor: NSColor(calibratedRed: 0.84, green: 0.79, blue: 0.72, alpha: 0.5))
    static let focusRing = Color(nsColor: NSColor(calibratedRed: 0.88, green: 0.58, blue: 0.38, alpha: 0.9))
}

/// Compact, elegant native SwiftUI emote selection component.
///
/// Presents Cookie's five predefined emotes with clear interactive states,
/// subtle hover treatments, visible keyboard focus states, cooldown feedback,
/// and instant keyboard triggers (1–5).
struct EmotePickerView: View {
    @EnvironmentObject private var behaviorEngine: CookieBehaviorEngine
    @EnvironmentObject private var environment: AppEnvironment

    @FocusState private var focusedEmoteId: EmoteId?
    @State private var hoveredEmoteId: EmoteId?
    @State private var cooldownTicker = Date()

    var onDismiss: (() -> Void)? = nil

    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(EmoteColors.subtleBorder)
            emoteList
            Divider().overlay(EmoteColors.subtleBorder)
            footer
        }
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(EmoteColors.warmWhite)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(EmoteColors.subtleBorder, lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onReceive(timer) { date in
            cooldownTicker = date
        }
        .onAppear {
            if focusedEmoteId == nil {
                focusedEmoteId = .wave
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(EmoteColors.softOrange)

            Text("Cookie Emotes")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(EmoteColors.darkCharcoal)

            Spacer()

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(EmoteColors.neutralGray)
                        .padding(5)
                        .background(
                            Circle()
                                .fill(EmoteColors.ivory)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Emotes")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(EmoteColors.cream)
    }

    // MARK: - Emote List

    private var emoteList: some View {
        VStack(spacing: 6) {
            ForEach(Array(Emote.allEmotes.enumerated()), id: \.element.id) { index, emote in
                emoteRow(emote: emote, index: index + 1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(EmoteColors.warmWhite)
    }

    // MARK: - Emote Row

    private func emoteRow(emote: Emote, index: Int) -> some View {
        let isFocused = focusedEmoteId == emote.id
        let isHovered = hoveredEmoteId == emote.id
        let cooldown = behaviorEngine.cooldownRemaining(for: emote.id)
        let isOnCooldown = cooldown > 0.05
        let isPlaying = behaviorEngine.activeEmote?.id == emote.id
        let isBusy = behaviorEngine.activeEmote != nil && !isPlaying
        let isDragged = behaviorEngine.state == .beingDragged
        let isDisabled = isOnCooldown || isBusy || isDragged

        return Button {
            guard !isDisabled else { return }
            _ = environment.triggerEmote(emote)
        } label: {
            HStack(spacing: 10) {
                // Icon tile
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            isPlaying
                                ? EmoteColors.warmPeach
                                : (isHovered ? EmoteColors.warmPeachHighlight : EmoteColors.ivory)
                        )
                        .frame(width: 34, height: 34)

                    Image(systemName: emote.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(
                            isPlaying
                                ? EmoteColors.softOrange
                                : (isOnCooldown ? EmoteColors.neutralGray : EmoteColors.warmBrown)
                        )
                }

                // Label and description
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(emote.name)
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundStyle(isDisabled ? EmoteColors.neutralGray : EmoteColors.darkCharcoal)

                        if isPlaying {
                            Text("Playing…")
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(EmoteColors.softOrange)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(
                                    Capsule()
                                        .fill(EmoteColors.warmPeach)
                                )
                        }
                    }

                    Text(emote.description)
                        .font(.system(size: 10.5))
                        .foregroundStyle(EmoteColors.neutralGray)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                // Cooldown countdown or index shortcut pill
                if isOnCooldown {
                    Text(String(format: "%.1fs", cooldown))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(EmoteColors.neutralGray)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(EmoteColors.ivory)
                        )
                } else {
                    Text("\(index)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(EmoteColors.warmBrown.opacity(0.7))
                        .frame(width: 18, height: 18)
                        .background(
                            Circle()
                                .fill(isHovered ? EmoteColors.warmPeach : EmoteColors.ivory)
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(
                        isPlaying
                            ? EmoteColors.warmPeachHighlight
                            : (isHovered ? EmoteColors.cream : Color.clear)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(
                        isFocused
                            ? EmoteColors.focusRing
                            : (isHovered ? EmoteColors.subtleBorder : Color.clear),
                        lineWidth: isFocused ? 2 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .focusable(true)
        .focused($focusedEmoteId, equals: emote.id)
        .onHover { inside in
            hoveredEmoteId = inside ? emote.id : nil
        }
        .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: [])
        .accessibilityLabel("\(emote.name) emote")
        .accessibilityHint(emote.description)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("Press 1–5 or Return to trigger")
                .font(.system(size: 10.5))
                .foregroundStyle(EmoteColors.neutralGray)

            Spacer()

            if behaviorEngine.activeEmote != nil {
                HStack(spacing: 4) {
                    Circle()
                        .fill(EmoteColors.softOrange)
                        .frame(width: 6, height: 6)
                    Text("Emoting")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(EmoteColors.warmBrown)
                }
            } else {
                Text("Ready")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(EmoteColors.mutedSage)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(EmoteColors.cream)
    }
}
