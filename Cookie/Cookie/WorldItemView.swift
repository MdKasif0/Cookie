import SwiftUI
import AppKit

/// Shows an item placed on the desktop (toys, foods, the cardboard box) using its
/// rendered art, with a wiggle while Cookie plays and a dismiss button on hover.
struct WorldItemView: View {
    let item: WorldItem
    var isInteracting: Bool = false
    var isEating: Bool = false
    var size: CGFloat = 80
    var onDismiss: (() -> Void)? = nil
    var onDragEnded: ((CGFloat) -> Void)? = nil

    @State private var isHovered: Bool = false
    @State private var dragOffset: CGSize = .zero
    @State private var wiggle: Bool = false

    private var assetName: String {
        item.isConsumed && item.kind.isFood ? "food-empty" : item.kind.assetName
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let art = CookieArtwork.image("Items", assetName) {
                    Image(nsImage: art)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .accessibilityLabel(item.kind.displayName)
                }
            }
            .frame(width: size, height: size)
            .rotationEffect(
                .degrees(isInteracting && !item.kind.isBox ? (wiggle ? 6 : -6) : 0),
                anchor: UnitPoint(x: 0.5, y: 0.9)
            )

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
        .frame(width: size, height: size)
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
        .onChange(of: isInteracting, initial: true) { _, interacting in
            guard interacting, !MotionSettings.reduceMotion else {
                withAnimation(.easeOut(duration: 0.15)) { wiggle = false }
                return
            }
            withAnimation(.easeInOut(duration: 0.22).repeatForever(autoreverses: true)) {
                wiggle = true
            }
        }
    }
}
