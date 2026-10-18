import SwiftUI

/// The full "How to scan" guide: the diagram and every setup tip. Opens from the intro and from the camera's "?".
@MainActor
struct ScanTipsSheet: View {
    let onDone: () -> Void

    private static let tips = [
        "Have a friend hold the phone. You stand still.",
        "Wipe the back camera lenses clean.",
        "Barefoot, with trousers rolled above the ankle.",
        "Weight on both feet, on a plain, non-shiny floor.",
        "Bright, even light, but not direct sun.",
        "Two slow laps: knee height, then near the floor.",
        "Hold still for about 2 minutes.",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                Text("How to scan")
                    .display(.title)
                    .accessibilityAddTraits(.isHeader)
                PositioningDiagram()
                VStack(spacing: 0) {
                    ForEach(Array(Self.tips.enumerated()), id: \.offset) { index, tip in
                        if index > 0 { Hairline() }
                        Text(tip)
                            .foregroundStyle(.ink2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, Space.md)
                    }
                }
            }
            .padding(.horizontal, Space.page)
            .padding(.top, Space.xl)
            .padding(.bottom, Space.lg)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Got it", action: onDone)
                .buttonStyle(.archyPrimary)
                .padding(.horizontal, Space.page)
                .padding(.bottom, Space.sm)
        }
        .archyScreen()
    }
}
