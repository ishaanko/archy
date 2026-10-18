//
//  FootScanApp.swift
//  FootScan
//
//  Created by Pranav Narsipur on 10/17/26.
//

import SwiftUI

@main
struct FootScanApp: App {
    @State private var model = ScanFlowModel()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "FootScanEmbedDemo") {
                EmbeddingDemoView()
            } else {
                ScanRootView()
                    .environment(model)
            }
            #else
            ScanRootView()
                .environment(model)
            #endif
        }
    }
}
