import SwiftUI
import AppKit

/// Visual presenter for items placed on the desktop (toys, foods, the cardboard box).
/// Crisp vector-drawn artwork styled with Cookie's warm palette, soft contact shadows,
/// playful micro-animations when Cookie interacts, and a subtle dismiss button on hover.
struct WorldItemView: View {
    let item: WorldItem
    var isInteracting: Bool = false
    var isEating: Bool = false
    var onDismiss: (() -> Void)? = nil
    var onDragEnded: ((CGFloat) -> Void)? = nil

    @State private var isHovered: Bool = false
    @State private var dragOffset: CGSize = .zero
    @State private var wigglePhase: Double = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Ground shadow
            Ellipse()
                .fill(Color.black.opacity(0.12))
                .frame(width: shadowWidth, height: 10)
                .offset(y: 26)

            // The item graphic
            Group {
                switch item.kind {
                case .toy(let toy):
                    toyView(for: toy)
                case .food(let food):
                    foodView(for: food)
                case .box:
                    boxView
                }
            }
            .offset(y: bounceOffset)
            .rotationEffect(.degrees(wiggleAngle))

            // Hover dismiss button (non-intrusive, so the user can easily tidy up)
            if isHovered {
                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
                }
                .buttonStyle(.plain)
                .offset(x: -4, y: 4)
                .help("Put away")
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .frame(width: 80, height: 80)
        .contentShape(Rectangle())
        .offset(dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = CGSize(width: value.translation.width, height: 0)
                }
                .onEnded { value in
                    let finalX = item.x + value.translation.width
                    dragOffset = .zero
                    onDragEnded?(finalX)
                }
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    // MARK: - Animation offsets

    private var bounceOffset: CGFloat {
        if isInteracting {
            return sin(wigglePhase) * 3
        }
        return 0
    }

    private var wiggleAngle: Double {
        if isInteracting {
            return cos(wigglePhase) * 6
        }
        return 0
    }

    private var shadowWidth: CGFloat {
        switch item.kind {
        case .box, .toy(.box): return 68
        case .toy(.yarnBall), .toy(.ball): return 34
        case .toy(.toyMouse): return 44
        case .toy(.feather), .toy(.fishToy): return 48
        case .food: return 52
        }
    }

    // MARK: - Toys

    @ViewBuilder
    private func toyView(for toy: ToyKind) -> some View {
        switch toy {
        case .yarnBall:
            yarnBallGraphic
        case .feather:
            featherGraphic
        case .toyMouse:
            toyMouseGraphic
        case .fishToy:
            fishToyGraphic
        case .ball:
            ballGraphic
        case .box:
            boxView
        }
    }

    private var yarnBallGraphic: some View {
        ZStack {
            // Curled loose thread trailing on the floor
            Path { path in
                path.move(to: CGPoint(x: 38, y: 50))
                path.addCurve(to: CGPoint(x: 62, y: 55),
                              control1: CGPoint(x: 46, y: 62),
                              control2: CGPoint(x: 54, y: 48))
            }
            .stroke(Color(red: 0.88, green: 0.44, blue: 0.44), style: StrokeStyle(lineWidth: 2, lineCap: .round))

            // Yarn core
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.94, green: 0.58, blue: 0.54), Color(red: 0.82, green: 0.38, blue: 0.38)],
                        center: .topLeading, startRadius: 4, endRadius: 24
                    )
                )
                .frame(width: 34, height: 34)

            // Wound strand lines
            Circle()
                .stroke(Color(red: 0.72, green: 0.28, blue: 0.28).opacity(0.4), lineWidth: 1.5)
                .frame(width: 26, height: 26)
            Circle()
                .stroke(Color(red: 0.96, green: 0.72, blue: 0.68).opacity(0.6), lineWidth: 1.2)
                .frame(width: 16, height: 16)
        }
    }

    private var featherGraphic: some View {
        ZStack {
            // Feather barbs & quill
            Path { path in
                path.move(to: CGPoint(x: 22, y: 56))
                path.addCurve(to: CGPoint(x: 58, y: 22),
                              control1: CGPoint(x: 32, y: 46),
                              control2: CGPoint(x: 48, y: 32))
            }
            .stroke(Color(red: 0.82, green: 0.70, blue: 0.52), style: StrokeStyle(lineWidth: 2, lineCap: .round))

            // Turquoise and warm gold vanes
            Path { path in
                path.move(to: CGPoint(x: 24, y: 54))
                path.addCurve(to: CGPoint(x: 58, y: 22),
                              control1: CGPoint(x: 30, y: 32),
                              control2: CGPoint(x: 44, y: 22))
                path.addCurve(to: CGPoint(x: 24, y: 54),
                              control1: CGPoint(x: 52, y: 36),
                              control2: CGPoint(x: 38, y: 56))
            }
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.32, green: 0.74, blue: 0.72), Color(red: 0.94, green: 0.74, blue: 0.38)],
                    startPoint: .bottomLeading, endPoint: .topTrailing
                )
            )
        }
    }

    private var toyMouseGraphic: some View {
        ZStack {
            // Tail
            Path { path in
                path.move(to: CGPoint(x: 22, y: 46))
                path.addCurve(to: CGPoint(x: 12, y: 34),
                              control1: CGPoint(x: 16, y: 48),
                              control2: CGPoint(x: 14, y: 40))
            }
            .stroke(Color(red: 0.85, green: 0.65, blue: 0.65), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))

            // Felt body
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.76, green: 0.74, blue: 0.72), Color(red: 0.58, green: 0.56, blue: 0.54)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 32, height: 20)
                .offset(x: 2, y: 2)

            // Pink ears
            Circle()
                .fill(Color(red: 0.94, green: 0.74, blue: 0.74))
                .frame(width: 8, height: 8)
                .offset(x: 0, y: -6)

            // Nose
            Circle()
                .fill(Color(red: 0.22, green: 0.20, blue: 0.18))
                .frame(width: 3.5, height: 3.5)
                .offset(x: 18, y: 2)
        }
    }

    private var fishToyGraphic: some View {
        ZStack {
            // Fabric fish body
            Path { path in
                path.move(to: CGPoint(x: 18, y: 42))
                path.addCurve(to: CGPoint(x: 54, y: 42),
                              control1: CGPoint(x: 32, y: 28),
                              control2: CGPoint(x: 44, y: 32))
                path.addCurve(to: CGPoint(x: 18, y: 42),
                              control1: CGPoint(x: 44, y: 52),
                              control2: CGPoint(x: 32, y: 56))
                // Tail fin
                path.addLine(to: CGPoint(x: 10, y: 34))
                path.addLine(to: CGPoint(x: 14, y: 42))
                path.addLine(to: CGPoint(x: 10, y: 50))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.44, green: 0.72, blue: 0.82), Color(red: 0.28, green: 0.54, blue: 0.66)],
                    startPoint: .top, endPoint: .bottom
                )
            )

            // Cross stitching details
            Path { path in
                path.move(to: CGPoint(x: 32, y: 36))
                path.addLine(to: CGPoint(x: 36, y: 46))
                path.move(to: CGPoint(x: 36, y: 36))
                path.addLine(to: CGPoint(x: 32, y: 46))
            }
            .stroke(Color.white.opacity(0.6), lineWidth: 1.2)

            // Button eye
            Circle()
                .fill(Color(red: 0.96, green: 0.88, blue: 0.62))
                .frame(width: 4.5, height: 4.5)
                .offset(x: 10, y: -2)
        }
    }

    private var ballGraphic: some View {
        ZStack {
            // Rubber ball
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.98, green: 0.84, blue: 0.38), Color(red: 0.90, green: 0.62, blue: 0.22)],
                        center: .topLeading, startRadius: 4, endRadius: 22
                    )
                )
                .frame(width: 32, height: 32)

            // Contrasting stripe
            Path { path in
                path.addArc(center: CGPoint(x: 40, y: 40), radius: 16, startAngle: .degrees(150), endAngle: .degrees(330), clockwise: false)
            }
            .stroke(Color(red: 0.94, green: 0.44, blue: 0.40), lineWidth: 5)
            .clipShape(Circle().size(width: 32, height: 32).offset(x: 24, y: 24))

            // Gloss highlight
            Circle()
                .fill(Color.white.opacity(0.55))
                .frame(width: 7, height: 7)
                .offset(x: -6, y: -6)
        }
    }

    // MARK: - Cardboard Box

    private var boxView: some View {
        ZStack {
            // Interior cavity
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(red: 0.58, green: 0.42, blue: 0.28))
                .frame(width: 60, height: 36)
                .offset(y: 4)

            // Front wall
            RoundedRectangle(cornerRadius: 3)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.82, green: 0.64, blue: 0.46), Color(red: 0.72, green: 0.54, blue: 0.38)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color(red: 0.52, green: 0.38, blue: 0.25), lineWidth: 1.2)
                )
                .frame(width: 64, height: 30)
                .offset(y: 10)

            // Packaging tape strip
            Rectangle()
                .fill(Color(red: 0.92, green: 0.88, blue: 0.76).opacity(0.6))
                .frame(width: 14, height: 30)
                .offset(y: 10)

            // Folded side flaps
            Path { path in
                path.move(to: CGPoint(x: 8, y: 38))
                path.addLine(to: CGPoint(x: 2, y: 30))
                path.addLine(to: CGPoint(x: 22, y: 30))
                path.addLine(to: CGPoint(x: 22, y: 38))
                path.closeSubpath()
            }
            .fill(Color(red: 0.76, green: 0.58, blue: 0.42))
            .overlay(
                Path { path in
                    path.move(to: CGPoint(x: 8, y: 38))
                    path.addLine(to: CGPoint(x: 2, y: 30))
                    path.addLine(to: CGPoint(x: 22, y: 30))
                }.stroke(Color(red: 0.52, green: 0.38, blue: 0.25), lineWidth: 1)
            )

            Path { path in
                path.move(to: CGPoint(x: 58, y: 38))
                path.addLine(to: CGPoint(x: 58, y: 30))
                path.addLine(to: CGPoint(x: 78, y: 30))
                path.addLine(to: CGPoint(x: 72, y: 38))
                path.closeSubpath()
            }
            .fill(Color(red: 0.76, green: 0.58, blue: 0.42))
            .overlay(
                Path { path in
                    path.move(to: CGPoint(x: 58, y: 30))
                    path.addLine(to: CGPoint(x: 78, y: 30))
                    path.addLine(to: CGPoint(x: 72, y: 38))
                }.stroke(Color(red: 0.52, green: 0.38, blue: 0.25), lineWidth: 1)
            )

            // Little stamp on front
            Image(systemName: "pawprint.fill")
                .font(.system(size: 8))
                .foregroundStyle(Color(red: 0.46, green: 0.32, blue: 0.20).opacity(0.45))
                .offset(x: 20, y: 14)
        }
    }

    // MARK: - Foods

    @ViewBuilder
    private func foodView(for food: FoodKind) -> some View {
        ZStack {
            // Saucer plate
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.98, green: 0.97, blue: 0.95), Color(red: 0.88, green: 0.87, blue: 0.84)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    Ellipse().stroke(Color(red: 0.74, green: 0.72, blue: 0.70), lineWidth: 1)
                )
                .frame(width: 48, height: 22)
                .offset(y: 12)

            if !item.isConsumed {
                switch food {
                case .fish:
                    // Fish fillet
                    Path { path in
                        path.move(to: CGPoint(x: 24, y: 48))
                        path.addCurve(to: CGPoint(x: 54, y: 48),
                                      control1: CGPoint(x: 36, y: 38),
                                      control2: CGPoint(x: 46, y: 40))
                        path.addCurve(to: CGPoint(x: 24, y: 48),
                                      control1: CGPoint(x: 46, y: 56),
                                      control2: CGPoint(x: 36, y: 56))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.46, green: 0.68, blue: 0.78), Color(red: 0.92, green: 0.62, blue: 0.58)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                case .milk:
                    // Saucer of white creamy milk
                    Ellipse()
                        .fill(Color.white)
                        .overlay(Ellipse().stroke(Color(red: 0.90, green: 0.92, blue: 0.94), lineWidth: 1))
                        .frame(width: 36, height: 14)
                        .offset(y: 11)
                case .chicken:
                    // Drumstick
                    ZStack {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.92, green: 0.64, blue: 0.32), Color(red: 0.78, green: 0.48, blue: 0.20)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .frame(width: 24, height: 14)
                            .rotationEffect(.degrees(-15))
                            .offset(x: -3, y: 8)
                        // Bone
                        Capsule()
                            .fill(Color(red: 0.98, green: 0.96, blue: 0.92))
                            .frame(width: 9, height: 5)
                            .offset(x: 12, y: 12)
                    }
                case .cookie:
                    // Baked cookie
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(red: 0.92, green: 0.74, blue: 0.48), Color(red: 0.78, green: 0.54, blue: 0.28)],
                                center: .center, startRadius: 2, endRadius: 14
                            )
                        )
                        .frame(width: 24, height: 24)
                        .offset(y: 8)
                    // Chocolate morsels
                    ForEach([(-4.0, 6.0), (3.0, 9.0), (-1.0, 12.0), (4.0, 5.0)], id: \.0) { pt in
                        Circle()
                            .fill(Color(red: 0.36, green: 0.22, blue: 0.14))
                            .frame(width: 3, height: 3)
                            .offset(x: pt.0, y: pt.1)
                    }
                }
            } else {
                // Empty clean dish with little sparkle
                Image(systemName: "sparkle")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(red: 0.96, green: 0.82, blue: 0.42))
                    .offset(y: 10)
            }
        }
    }
}
