import SwiftUI

/// A bed, sunbeam or scratching post on the desktop: drag it sideways to move it,
/// or click the small x that appears on hover to put it away.
struct CozyItemView: View {
    let kind: CozyKind
    let side: CGFloat
    var onDismiss: (() -> Void)?
    var onDragEnded: ((CGFloat) -> Void)?

    @State private var isHovered = false
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let art = CookieArtwork.image("Items", kind.assetName) {
                Image(nsImage: art)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: side, height: side)
                    .accessibilityLabel(kind.displayName)
            }
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
                .help("Put away")
                .padding(6)
                .transition(.opacity)
            }
        }
        .frame(width: side, height: side)
        .contentShape(Rectangle())
        .offset(x: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { dragOffset = $0.translation.width }
                .onEnded { value in
                    dragOffset = 0
                    onDragEnded?(value.translation.width)
                }
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
    }
}
