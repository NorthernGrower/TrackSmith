//
//  ShareSheet.swift
//  AI Music Studio
//

import SwiftUI
import UIKit

/// Presents the system share sheet for a file the studio has written.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onCompletion: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        let completion = onCompletion
        controller.completionWithItemsHandler = { _, _, _, _ in
            DispatchQueue.main.async {
                completion?()
            }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// A file waiting to be handed to the share sheet.
struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}
