import SwiftUI

@main
struct ArchyApp: App {
    @StateObject private var assessments = AssessmentStore()
    @State private var onboarding = OnboardingStore()
    @State private var requests = InsoleRequestStore()
    @State private var scan = ScanFlowModel()
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(assessments)
                .environment(onboarding)
                .environment(requests)
                .environment(scan)
                .environment(router)
        }
    }
}
