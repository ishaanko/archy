import SwiftUI

/// Insole tab entry point. Owns its NavigationStack.
/// Debug routes (-ArchyRoute): insole.studio, insole.mars, insole.request, insole.saved, insole.research.
struct InsoleTab: View {
    @Environment(AppRouter.self) private var router
    var body: some View { InsoleNavigation(debugRoute: router.debugRoute) }
}

private struct InsoleNavigation: View {
    @Environment(InsoleRequestStore.self) private var store
    @State private var path: [InsoleRoute]

    init(debugRoute: String?) {
        var path: [InsoleRoute] = []
        #if DEBUG
        if debugRoute == "insole.saved" { path = [.saved] }
        if debugRoute == "insole.research" { path = [.research] }
        #endif
        _path = State(initialValue: path)
        self.debugRoute = debugRoute
    }
    private let debugRoute: String?

    var body: some View {
        NavigationStack(path: $path) {
            InsoleStudioView(debugRoute: debugRoute)
                .navigationDestination(for: InsoleRoute.self) { route in
                    switch route {
                    case .saved: SavedRequestsView()
                    case .research: ResearchView()
                    case .request(let id):
                        if let request = store.requests.first(where: { $0.id == id }) { SavedRequestView(request: request) }
                    }
                }
        }
    }
}
