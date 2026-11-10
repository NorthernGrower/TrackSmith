//
//  AI_Music_StudioApp.swift
//  AI Music Studio
//

import SwiftUI

@main
struct AI_Music_StudioApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        CrashReporter.shared.install()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                CrashReporter.shared.endSession()
            }
        }
    }
}
