//
//  CaptureView.swift
//  FootScan
//

import RealityKit
import SwiftUI

/// Camera feed for ready → detecting → capturing → finishing, with our controls on top.
/// Stays mounted for the whole session so the camera never restarts mid-scan.
@MainActor
struct CaptureView: View {
    let session: ObjectCaptureSession

    var body: some View {
        ZStack {
            ObjectCaptureView(session: session) {
                // Darkens the top and bottom of the feed so the white controls stay readable.
                VStack {
                    LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 200)
                    Spacer()
                    LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 260)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            CaptureControls(session: session)
        }
        .id(session.id)
    }
}
