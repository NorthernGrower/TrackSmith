//
//  AgentChatDrawer.swift
//  AI Music Studio
//

import SwiftUI

/// The slide-up chat drawer over the mixer: conversation bubbles and a prompt box.
struct AgentChatDrawer: View {
    @ObservedObject var chat: AgentChatViewModel
    var onClose: () -> Void

    private struct Bubble: View {
        let message: ChatMessage

        var body: some View {
            HStack {
                if message.isUser { Spacer(minLength: 40) }
                Text(message.text)
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        message.isUser ? Color.studioAccent : Color.studioPanelHighlight,
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                    .foregroundStyle(message.isUser ? Color.black : Color.primary)
                if !message.isUser { Spacer(minLength: 40) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(white: 0.35))
                .frame(width: 40, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 6)

            HStack {
                Text("Studio Agent")
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "chevron.down")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(chat.messages) { message in
                        Bubble(message: message)
                    }
                }
                .padding(.vertical, 8)
            }
            .defaultScrollAnchor(.bottom)
            .background(Color.studioBackground)

            HStack(spacing: 10) {
                TextField("Tell the agent what to change…", text: $chat.draft, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.studioPanelHighlight, in: RoundedRectangle(cornerRadius: 14))
                    .submitLabel(.send)
                    .onSubmit { chat.send() }

                Button(action: chat.send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(chat.draft.trimmingCharacters(in: .whitespaces).isEmpty || chat.isWaiting)
            }
            .padding(12)
            .background(Color.studioPanel)
        }
        .background(Color.studioPanel)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
    }
}
