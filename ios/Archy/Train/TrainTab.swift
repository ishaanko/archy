import SwiftUI

enum TrainRoute: Hashable {
    case shortFoot, balance
    #if DEBUG
    case shortFootHold, balanceHold, done
    #endif
}

/// Train tab entry point. Owns its NavigationStack.
/// Debug routes: train.library, train.shortfoot, train.shortfoot.hold, train.balance, train.balance.hold, train.done.
struct TrainTab: View {
    @Environment(AppRouter.self) private var router
    @State private var path: [TrainRoute] = []
    @State private var openedDebugRoute = false

    var body: some View {
        NavigationStack(path: $path) {
            ExerciseLibraryView()
                .navigationDestination(for: TrainRoute.self) { route in
                    switch route {
                    case .shortFoot: ExerciseCoachView()
                    case .balance: BalanceCoachView()
                    #if DEBUG
                    case .shortFootHold: ExerciseCoachView(debugElapsed: 21)
                    case .balanceHold: BalanceCoachView(debugElapsed: 8)
                    case .done:
                        CoachCompletion(fact: CoachProgram.shortFoot.finishedFact) { path.removeAll() }
                            .archyScreen()
                            .toolbar(.hidden, for: .navigationBar)
                            .toolbar(.hidden, for: .tabBar)
                    #endif
                    }
                }
        }
        #if DEBUG
        .onAppear {
            guard !openedDebugRoute else { return }
            openedDebugRoute = true
            switch router.debugRoute {
            case "train.shortfoot": path = [.shortFoot]
            case "train.shortfoot.hold": path = [.shortFootHold]
            case "train.balance": path = [.balance]
            case "train.balance.hold": path = [.balanceHold]
            case "train.done": path = [.done]
            default: break
            }
        }
        #endif
    }
}

struct ExerciseLibraryView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                Text("Train").display(.hero).reveal(0)
                NavigationLink(value: TrainRoute.shortFoot) {
                    ExerciseCard(title: "Short foot", fact: "Seated · 5 reps · 1 min") { lift in
                        CoachFootDiagram(lift: lift)
                    }
                }
                .buttonStyle(.archyPressable)
                .accessibilityIdentifier("studio.shortFoot")
                .reveal(1)
                NavigationLink(value: TrainRoute.balance) {
                    ExerciseCard(title: "Tandem balance", fact: "Standing · 2 holds · 1 min") { stance in
                        BalanceStanceDiagram(tandem: stance > 0.5, leftLeads: true, holding: false)
                    }
                }
                .buttonStyle(.archyPressable)
                .accessibilityIdentifier("studio.balance")
                .reveal(2)
            }
            .padding(.horizontal, Space.page)
            .padding(.top, Space.lg)
            .padding(.bottom, Space.xxl)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .archyScreen()
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// A library card: a small diagram that plays the movement once when it appears, then the name and one fact.
private struct ExerciseCard<Visual: View>: View {
    let title: String
    let fact: String
    @ViewBuilder let visual: (Double) -> Visual
    @State private var played = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Color.clear
                .frame(height: 124)
                .overlay {
                    // Runs 0 -> 1 -> 0 once when `played` flips, then rests.
                    Color.clear.phaseAnimator([0.0, 1.0], trigger: played) { _, amount in
                        visual(amount).frame(height: 124)
                    } animation: { _ in Motion.smooth }
                }
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title).display(.headline)
                Text(fact).font(.subheadline).foregroundStyle(.inkSecondary)
            }
        }
        .surface()
        .task {
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .milliseconds(500))
            played = true
        }
    }
}
