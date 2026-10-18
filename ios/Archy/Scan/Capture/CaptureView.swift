import RealityKit
import SwiftUI

/// Full-screen camera feed for ready → detecting → capturing → finishing, with our controls on top.
/// Stays mounted for the whole session so the camera never restarts mid-scan.
@MainActor
struct CaptureView: View {
    @Environment(ScanFlowModel.self) private var model
    let session: ObjectCaptureSession

    var body: some View {
        ZStack {
            ObjectCaptureView(session: session) {
                CaptureScrims()
            }

            CaptureControls(session: session)
        }
        .background(Color.black)
        .id(session.id)
        // On this screen so it presents over the camera cover. The session resumes in onDismiss,
        // after the sheet has finished animating away.
        .sheet(isPresented: Binding(get: { model.isShowingTips }, set: { model.setTipsPresented($0) }),
               onDismiss: { model.tipsDismissed() }) {
            ScanTipsSheet { model.setTipsPresented(false) }
        }
    }
}

/// Darkens the top and bottom of the camera feed so the white controls stay readable.
struct CaptureScrims: View {
    var body: some View {
        VStack {
            LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 200)
            Spacer()
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .frame(height: 300)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
