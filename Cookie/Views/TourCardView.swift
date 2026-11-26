import SwiftUI

/// One step of the helpers tour, shown beside Cookie.
struct TourCardView: View {
    let step: HelpersTour.Step
    let index: Int
    let count: Int
    let onTry: () -> Void
    let onNext: () -> Void
    let onSkip: () -> Void

    private var isLast: Bool { index == count - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                ForEach(0..<count, id: \.self) { dot in
                    Capsule()
                        .fill(dot == index ? Color.cookieAccent : Color.secondary.opacity(0.3))
                        .frame(width: dot == index ? 14 : 6, height: 6)
                }
                Spacer(minLength: 8)
                if !isLast {
                    Button("Skip Tour", action: onSkip)
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(index + 1) of \(count)")

            Text(step.title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
            Text(step.text)
                .font(.system(size: 12.5, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if let tryTitle = step.tryTitle {
                    Button(tryTitle, action: onTry)
                        .controlSize(.small)
                }
                Spacer()
                Button(isLast ? "Done" : "Next", action: onNext)
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(width: 260)
        .cookieGlass(cornerRadius: 16)
        .padding(6)
    }
}
