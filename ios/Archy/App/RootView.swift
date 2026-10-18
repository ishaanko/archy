import SwiftUI

/// Onboarding until the quiz is complete, then the four tabs.
struct RootView: View {
    @Environment(OnboardingStore.self) private var onboarding
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("accessibility.readingFriendly") private var readingFriendly = false

    var body: some View {
        ZStack {
            if onboarding.completed != nil {
                tabs.transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                OnboardingView { answers in
                    if onboarding.complete(answers) { router.tab = .scan }
                }
                .transition(.opacity)
            }
        }
        .animation(Motion.smooth.reduced(reduceMotion), value: onboarding.completed != nil)
        .archyScreen()
        .fontDesign(readingFriendly ? .rounded : .default)
        .lineSpacing(readingFriendly ? 6 : 2)
    }

    private var tabs: some View {
        @Bindable var router = router
        return TabView(selection: $router.tab) {
            Tab("Home", systemImage: "house", value: AppTab.home) { HomeTab() }
            Tab("Scan", systemImage: "viewfinder", value: AppTab.scan) { ScanTab() }
            Tab("Insole", systemImage: "shoeprints.fill", value: AppTab.insole) { InsoleTab() }
            Tab("Train", systemImage: "figure.walk", value: AppTab.train) { TrainTab() }
        }
        .sensoryFeedback(.selection, trigger: router.tab)
    }
}
