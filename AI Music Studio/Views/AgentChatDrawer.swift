//
//  AgentChatDrawer.swift
//  AI Music Studio
//

import SwiftUI

/// The chat sheet over the mixer: conversation bubbles and a prompt box.
struct AgentChatDrawer: View {
    @ObservedObject var chat: AgentChatViewModel
    var onClose: () -> Void

    @FocusState private var isInputFocused: Bool

    private struct Bubble: View {
        let message: ChatMessage

        var body: some View {
            HStack(alignment: .bottom) {
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
            header
            Divider()

            conversation

            Divider()

            inputBar
        }
        .background(Color.studioPanel)
        .onAppear {
            // Open ready to type, once the sheet has finished presenting.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                isInputFocused = true
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Studio Agent")
                    .font(.headline)
                Text("Ask for mixer changes in plain language")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close agent")
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(chat.messages) { message in
                        Bubble(message: message)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("chatBottom")
                }
                .padding(.vertical, 8)
            }
            .defaultScrollAnchor(.bottom)
            .background(Color.studioBackground)
            .onChange(of: chat.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("chatBottom", anchor: .bottom)
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Tell the agent what to change…", text: $chat.draft, axis: .vertical)
                .font(.subheadline)
                .lineLimit(1...4)
                .focused($isInputFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.studioPanelHighlight, in: RoundedRectangle(cornerRadius: 14))
                .submitLabel(.send)
                .onSubmit { chat.send() }
                .accessibilityLabel("Message the studio agent")

            Button(action: chat.send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? Color.studioAccent : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send message")
        }
        .padding(12)
        .background(Color.studioPanel)
    }

    private var canSend: Bool {
        !chat.draft.trimmingCharacters(in: .whitespaces).isEmpty && !chat.isWaiting
    }
}
