//
//  EmbeddingDemoView.swift
//  FootScan
//

#if DEBUG
import SwiftUI

/// Debug builds only: a stand-in host app for checking `FootScannerView` the way another app will use it.
/// Launch with `-FootScanEmbedDemo YES`.
@MainActor
struct EmbeddingDemoView: View {
    @State private var isScanning = false
    @State private var lastResult: FootScanResult?
    @State private var closedWithoutScan = 0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Open Scanner", systemImage: "camera.viewfinder") { isScanning = true }
                }
                if let result = lastResult {
                    Section("Last result") {
                        LabeledContent("STL", value: FileManager.default.fileExists(atPath: result.stlURL.path)
                                       ? result.stlURL.lastPathComponent : "missing!")
                        LabeledContent("Size", value: String(format: "%.1f × %.1f × %.1f cm",
                                                             result.lengthCM, result.widthCM, result.heightCM))
                        LabeledContent("Arch", value: result.archType.map {
                            "\($0.rawValue) (\(String(format: "%.1f", result.archHeightMM ?? 0)) mm)"
                        } ?? "not measured")
                        if let length = result.footLengthCM, let width = result.footWidthCM {
                            LabeledContent("Foot", value: String(format: "%.1f × %.1f cm", length, width))
                        }
                        Text(result.stlURL.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if closedWithoutScan > 0 {
                    Section {
                        Text("Closed without a scan: \(closedWithoutScan)×")
                    }
                }
            }
            .navigationTitle("Host App (Demo)")
        }
        .fullScreenCover(isPresented: $isScanning) {
            FootScannerView(onComplete: { result in
                lastResult = result
                isScanning = false
            }, onCancel: {
                closedWithoutScan += 1
                isScanning = false
            })
        }
    }
}
#endif
