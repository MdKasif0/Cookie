import SwiftUI

/// What Cookie says: greetings, focus reminders, new friendship levels.
struct BubbleView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: 230)
            .fixedSize(horizontal: false, vertical: true)
            .cookieGlass(cornerRadius: 14)
            .padding(6)
            .accessibilityLabel("Cookie says: \(text)")
    }
}
