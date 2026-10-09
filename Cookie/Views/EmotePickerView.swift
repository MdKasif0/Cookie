import SwiftUI
import Combine

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
    static let subtleBorder = Color(nsColor: NSColor(calibratedRed: 0.84, green: 0.79, blue: 0.72, alpha: 0.55))
    static let focusRing = Color(nsColor: NSColor(calibratedRed: 0.88, green: 0.58, blue: 0.38, alpha: 0.9))
}

/// Helper mapping each predefined emote to its authentic character artwork in the asset catalog.
enum EmoteArtwork {
    static func assetName(for id: EmoteId) -> String {
        switch id {
        case .wave: return "cookie-wave"
        case .happy: return "cookie-eyes-close"
        case .love: return "cookie-shy"
        case .sleepy: return "cookie-sleep"
        case .playful: return "cookie-mischievous"
        }
    }

    static func image(for id: EmoteId) -> NSImage? {
        NSImage(named: NSImage.Name(assetName(for: id)))
    }
}

/// Compact, premium native SwiftUI emote picker popover.
///
/// Features a balanced two-row grid:
///   [ Wave ]   [ Happy ]   [ Love ]
///        [ Sleepy ]   [ Playful ]
///
/// Fully keyboard accessible (1–5 triggers, arrow key navigation, Return, Esc),
/// authentic Cookie character artwork previews, subtle hover lift, and immediate
/// desktop feedback.
struct EmotePickerView: View {
    @EnvironmentObject private var behaviorEngine: CookieBehaviorEngine
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @FocusState private var focusedEmoteId: EmoteId?
    @State private var hoveredEmoteId: EmoteId?
    @State private var pressedEmoteId: EmoteId?
    @State private var cooldownTicker = Date()

    var onDismiss: (() -> Void)? = nil

    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(EmoteColors.subtleBorder)
            gridSection
            Divider().overlay(EmoteColors.subtleBorder)
            footer
        }
        .frame(width: 300)
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
        // Handle keyboard arrow keys, return, space, and escape
        .onKeyPress(.leftArrow) {
            navigateFocus(direction: .left)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            navigateFocus(direction: .right)
            return .handled
        }
        .onKeyPress(.upArrow) {
            navigateFocus(direction: .up)
            return .handled
        }
        .onKeyPress(.downArrow) {
            navigateFocus(direction: .down)
            return .handled
        }
        .onKeyPress(.return) {
            if let id = focusedEmoteId {
                selectEmote(Emote.find(id))
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.space) {
            if let id = focusedEmoteId {
                selectEmote(Emote.find(id))
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            onDismiss?()
            return .handled
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Emotes")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(EmoteColors.darkCharcoal)

                Text("Choose a little moment for Cookie.")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(EmoteColors.neutralGray)
            }

            Spacer()

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(EmoteColors.neutralGray)
                        .padding(5)
                        .background(
                            Circle()
                                .fill(EmoteColors.ivory)
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close Emotes")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(EmoteColors.cream)
    }

    // MARK: - Emote Grid

    private var gridSection: some View {
        VStack(spacing: 8) {
            // Row 1: [ Wave ] [ Happy ] [ Love ]
            HStack(spacing: 8) {
                emoteTile(emote: .wave, index: 1)
                emoteTile(emote: .happy, index: 2)
                emoteTile(emote: .love, index: 3)
            }

            // Row 2: [ Sleepy ] [ Playful ] (centered)
            HStack(spacing: 8) {
                emoteTile(emote: .sleepy, index: 4)
                emoteTile(emote: .playful, index: 5)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(EmoteColors.warmWhite)
    }

    // MARK: - Emote Tile

    private func emoteTile(emote: Emote, index: Int) -> some View {
        let isFocused = focusedEmoteId == emote.id
        let isHovered = hoveredEmoteId == emote.id
        let isPressed = pressedEmoteId == emote.id
        let cooldown = behaviorEngine.cooldownRemaining(for: emote.id)
        let isOnCooldown = cooldown > 0.05
        let isPlaying = behaviorEngine.activeEmote?.id == emote.id
        let isBusy = behaviorEngine.activeEmote != nil && !isPlaying
        let isDragged = behaviorEngine.state == .beingDragged
        let isDisabled = isOnCooldown || isBusy || isDragged

        return Button {
            selectEmote(emote)
        } label: {
            VStack(spacing: 3) {
                // Character Artwork Preview + Prominent Emoji Badge
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            isPlaying
                                ? EmoteColors.warmPeach
                                : (isHovered ? EmoteColors.warmPeachHighlight : EmoteColors.ivory)
                        )
                        .frame(width: 50, height: 50)

                    if let nsImage = EmoteArtwork.image(for: emote.id) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: emote.icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(
                                isPlaying
                                    ? EmoteColors.softOrange
                                    : (isOnCooldown ? EmoteColors.neutralGray : EmoteColors.warmBrown)
                            )
                    }

                    // Prominent Emoji Badge
                    Text(emote.emoji)
                        .font(.system(size: 13))
                        .padding(2.5)
                        .background(
                            Circle()
                                .fill(EmoteColors.warmWhite.opacity(0.96))
                                .shadow(color: Color.black.opacity(0.12), radius: 1.5, x: 0, y: 1)
                        )
                        .offset(x: 5, y: -5)
                }

                // Short Name
                Text(emote.name)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(isDisabled ? EmoteColors.neutralGray : EmoteColors.darkCharcoal)
                    .lineLimit(1)

                // Subtitle / Cooldown / Status hint
                if isOnCooldown {
                    Text(String(format: "%.1fs", cooldown))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(EmoteColors.neutralGray)
                } else if isPlaying {
                    Text("Active")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(EmoteColors.softOrange)
                } else {
                    Text("\(index)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(EmoteColors.warmBrown.opacity(0.55))
                }
            }
            .frame(width: 84, height: 88)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        isPressed
                            ? EmoteColors.warmPeach
                            : (isPlaying
                                ? EmoteColors.warmPeachHighlight
                                : (isHovered ? EmoteColors.cream : EmoteColors.warmWhite))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isFocused
                            ? EmoteColors.focusRing
                            : (isHovered ? EmoteColors.subtleBorder : EmoteColors.subtleBorder.opacity(0.4)),
                        lineWidth: isFocused ? 2 : 1
                    )
            )
            .offset(y: (isHovered && !reduceMotion) ? -1.5 : 0)
            .scaleEffect((isPressed && !reduceMotion) ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: isHovered)
            .animation(.easeInOut(duration: 0.08), value: isPressed)
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
        .accessibilityLabel("\(emote.name) \(emote.emoji) emote")
        .accessibilityHint("\(emote.description). Shortcut key \(index).")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Trigger & Dismissal

    private func selectEmote(_ emote: Emote) {
        let cooldown = behaviorEngine.cooldownRemaining(for: emote.id)
        guard cooldown <= 0.05 else { return }
        guard behaviorEngine.state != .beingDragged else { return }
        guard behaviorEngine.activeEmote == nil else { return }

        // Give immediate pressed visual feedback
        pressedEmoteId = emote.id

        // Trigger animation immediately on Cookie's desktop companion
        _ = environment.triggerEmote(emote)

        // Dismiss picker after a brief moment so user observes click register
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            if pressedEmoteId == emote.id {
                pressedEmoteId = nil
            }
            onDismiss?()
        }
    }

    // MARK: - Arrow Key Navigation

    private enum FocusDirection { case left, right, up, down }

    private func navigateFocus(direction: FocusDirection) {
        guard let current = focusedEmoteId else {
            focusedEmoteId = .wave
            return
        }

        switch (current, direction) {
        // Wave (Row 1, Col 1)
        case (.wave, .right): focusedEmoteId = .happy
        case (.wave, .down): focusedEmoteId = .sleepy

        // Happy (Row 1, Col 2)
        case (.happy, .left): focusedEmoteId = .wave
        case (.happy, .right): focusedEmoteId = .love
        case (.happy, .down): focusedEmoteId = .sleepy

        // Love (Row 1, Col 3)
        case (.love, .left): focusedEmoteId = .happy
        case (.love, .down): focusedEmoteId = .playful

        // Sleepy (Row 2, Col 1)
        case (.sleepy, .left): focusedEmoteId = .wave
        case (.sleepy, .right): focusedEmoteId = .playful
        case (.sleepy, .up): focusedEmoteId = .happy

        // Playful (Row 2, Col 2)
        case (.playful, .left): focusedEmoteId = .sleepy
        case (.playful, .up): focusedEmoteId = .love
        case (.playful, .right): focusedEmoteId = .love

        default: break
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("Press 1–5 to play • Esc to close")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(EmoteColors.neutralGray)

            Spacer()

            if behaviorEngine.activeEmote != nil {
                HStack(spacing: 4) {
                    Circle()
                        .fill(EmoteColors.softOrange)
                        .frame(width: 5, height: 5)
                    Text("Emoting")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(EmoteColors.warmBrown)
                }
            } else {
                Text("Ready")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(EmoteColors.mutedSage)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(EmoteColors.cream)
    }
}

