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
            ScanRootView()
                .environment(model)
        }
    }
}
