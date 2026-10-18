//
//  FootScannerView.swift
//  FootScan
//

import SwiftUI

/// The whole scanner as one screen for another app. Present it full screen:
///
///     .fullScreenCover(isPresented: $isScanning) {
///         FootScannerView(onComplete: { result in isScanning = false; use(result.stlURL) },
///                         onCancel: { isScanning = false })
///     }
///
/// `onComplete` runs when the user taps Done on a finished scan; `onCancel` when they close the scanner.
/// The presenting app dismisses the scanner in both.
@MainActor
struct FootScannerView: View {
    @State private var model: ScanFlowModel

    init(onComplete: @escaping (FootScanResult) -> Void, onCancel: @escaping () -> Void) {
        _model = State(initialValue: ScanFlowModel(onComplete: onComplete, onClose: onCancel))
    }

    var body: some View {
        ScanRootView()
            .environment(model)
    }
}
