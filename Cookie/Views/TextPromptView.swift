import SwiftUI

/// A one-field sheet used for new sticky notes and to-do items.
struct TextPromptView: View {
    let title: String
    let placeholder: String
    let actionTitle: String
    let multiline: Bool
    let maximumLength: Int
    let onDone: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @FocusState private var focused: Bool

    init(title: String, placeholder: String, actionTitle: String, initialText: String = "",
         multiline: Bool = false, maximumLength: Int = 120,
         onDone: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.title = title
        self.placeholder = placeholder
        self.actionTitle = actionTitle
        self.multiline = multiline
        self.maximumLength = maximumLength
        self.onDone = onDone
        self.onCancel = onCancel
        _text = State(initialValue: initialText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            Group {
                if multiline {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .lineLimit(4...8)
                } else {
                    TextField(placeholder, text: $text)
                        .onSubmit(done)
                }
            }
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .accessibilityLabel(title)
            .onChange(of: text) { _, value in
                if value.count > maximumLength { text = String(value.prefix(maximumLength)) }
            }
            HStack {
                if multiline {
                    Text("\(text.count)/\(maximumLength)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(actionTitle, action: done)
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .padding(.top, 8)
        .frame(width: 360)
        .onAppear { focused = true }
    }

    private func done() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onDone(trimmed)
    }
}
