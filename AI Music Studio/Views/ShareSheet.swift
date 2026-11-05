//
//  ShareSheet.swift
//  AI Music Studio
//

import SwiftUI
import UIKit

/// Presents the system share sheet for a file the studio has written.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// A file waiting to be handed to the share sheet.
struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}
