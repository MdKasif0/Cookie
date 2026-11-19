import SwiftUI

/// "Remind me in 20 minutes to…" Leave the text empty for a plain timer.
struct NewReminderView: View {
    let name: String
    let onAdd: (String, Int) -> Void
    let onCancel: () -> Void

    @State private var text = ""
    @State private var minutes = 20
    @FocusState private var textFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What should \(name) remind you about?")
                .font(.headline)
            TextField("Call Mom, stretch, take the pizza out…", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($textFocused)
                .onSubmit(add)
                .accessibilityLabel("Reminder text")
            Picker("Remind me in", selection: $minutes) {
                ForEach(CookieReminder.presetMinutes, id: \.self) { value in
                    Text(CookieReminder.label(forMinutes: value)).tag(value)
                }
            }
            Text("Leave the text empty for a simple timer. She'll come to your cursor and meow when it's time.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Remind Me", action: add)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .padding(.top, 8)
        .frame(width: 360)
        .onAppear { textFocused = true }
    }

    private func add() {
        onAdd(text, minutes)
    }
}
