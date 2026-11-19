import SwiftUI

/// The "Ask Cookie" chat window.
struct AskCookieView: View {
    @ObservedObject var chat: ChatController
    let name: String
    let openSettings: () -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if chat.lines.isEmpty {
                            Text("Ask \(name) anything. Your questions go to Claude, Anthropic's AI, using your own API key. Nothing is saved after you close this window.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                        ForEach(chat.lines) { line in
                            bubble(line).id(line.id)
                        }
                        if chat.isThinking {
                            Text("\(name) is thinking…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .id("thinking")
                        }
                    }
                    .padding(14)
                }
                .onChange(of: chat.lines.count) { _, _ in
                    withAnimation { proxy.scrollTo(chat.lines.last?.id, anchor: .bottom) }
                }
            }
            Divider()
            if chat.isReady {
                HStack(spacing: 8) {
                    TextField("Ask \(name)…", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.plain)
                        .focused($focused)
                        .onSubmit(send)
                        .accessibilityLabel("Question for \(name)")
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .buttonStyle(.borderless)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat.isThinking)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel("Send")
                }
                .padding(12)
            } else {
                HStack {
                    Text("Turn on Ask Cookie and add your Claude API key to start.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Settings", action: openSettings)
                }
                .padding(12)
            }
        }
        .frame(minWidth: 360, idealWidth: 400, minHeight: 380, idealHeight: 460)
        .toolbar {
            Button("New Chat") { chat.reset() }
                .disabled(chat.lines.isEmpty)
        }
        .onAppear { focused = true }
    }

    private func send() {
        let text = draft
        draft = ""
        chat.ask(text)
    }

    @ViewBuilder
    private func bubble(_ line: ChatLine) -> some View {
        switch line.speaker {
        case .you:
            HStack {
                Spacer(minLength: 40)
                Text(line.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor.opacity(0.18)))
            }
        case .cookie:
            HStack(alignment: .top, spacing: 8) {
                Text("🐱").accessibilityHidden(true)
                Text(line.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.12)))
                Spacer(minLength: 40)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(name) says: \(line.text)")
        case .notice:
            Text(line.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }
}
