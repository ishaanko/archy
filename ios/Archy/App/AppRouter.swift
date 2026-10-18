import Foundation
import Observation

/// The four tabs, in tab-bar order.
enum AppTab: String, CaseIterable, Hashable {
    case home, scan, insole, train
}

/// App-wide navigation state. Any screen can switch tabs with `router.tab = .scan`.
@MainActor
@Observable
final class AppRouter {
    var tab: AppTab = .home

    /// Debug builds only: `-ArchyRoute <value>` lets a feature open a deep screen at launch for
    /// screenshots and UI tests (for example `measure.wizard`). Each feature reads and interprets its own prefix.
    let debugRoute: String?

    init() {
        #if DEBUG
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: "ArchyTab"), let tab = AppTab(rawValue: raw) { self.tab = tab }
        debugRoute = defaults.string(forKey: "ArchyRoute")
        #else
        debugRoute = nil
        #endif
    }
}
