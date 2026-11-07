//
//  AgentAssistantAccess.swift
//  AI Music Studio
//

import SwiftUI

/// A shared, contextual assistant button that can sit over any studio page.
struct AgentAssistantAccess: ViewModifier {
    @EnvironmentObject private var chat: AgentChatViewModel
    @State private var isShowingAssistant = false

    let context: String

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                Button {
                    chat.setContext(context)
                    isShowingAssistant = true
                } label: {
                    Label("AI", systemImage: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 15)
                        .frame(height: 44)
                        .background(Color.studioAccent, in: Capsule())
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open AI assistant for \(context)")
                .padding(.trailing, 16)
                .padding(.bottom, 112)
                .sheet(isPresented: $isShowingAssistant) {
                    AgentChatDrawer(chat: chat) {
                        isShowingAssistant = false
                    }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(Color.studioPanel)
                }
            }
            .onAppear { chat.setContext(context) }
    }
}

extension View {
    func studioAgentAccess(context: String) -> some View {
        modifier(AgentAssistantAccess(context: context))
    }
}
