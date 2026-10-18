//
//  ShareSheet.swift
//  FootScan
//

import SwiftUI
import UIKit
import os

/// The system share sheet (AirDrop, Save to Files, …) for a list of files. Logs how sharing ended.
@MainActor
struct ShareSheet: UIViewControllerRepresentable {
    let items: [URL]
    /// Called when the share sheet closes itself, so the presenter can reset its state and Share works again.
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { activity, completed, _, error in
            let activityName = activity?.rawValue ?? "none"
            if let error {
                Log.viewer.error("Share via \(activityName, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            } else {
                Log.viewer.notice("Share via \(activityName, privacy: .public) \(completed ? "completed" : "dismissed", privacy: .public)")
            }
            onFinish()
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
