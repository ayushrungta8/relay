import SwiftUI

struct RelayChatView: View {
    let messages: [RelayChatMessage]

    var body: some View {
        if messages.isEmpty {
            ContentUnavailableView {
                Label("Ask Relay", systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text("Type below or hold Option-Space to ask about your Codex tasks.")
            }
            .foregroundStyle(RelayPalette.secondaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(messages) { message in
                            RelayChatMessageView(message: message)
                                .id(message.id)

                            if message.id != messages.last?.id {
                                Divider()
                                    .overlay(RelayPalette.hairline)
                                    .padding(.leading, 18)
                            }
                        }
                    }
                }
                .onChange(of: messages.last?.text, initial: true) { _, _ in
                    scrollToLatestMessage(using: proxy)
                }
            }
        }
    }

    private func scrollToLatestMessage(using proxy: ScrollViewProxy) {
        guard let latestID = messages.last?.id else { return }
        Task { @MainActor in
            await Task.yield()
            proxy.scrollTo(latestID, anchor: .bottom)
        }
    }
}
