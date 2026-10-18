import SwiftUI

/// The Scan tab at rest: how a scan works in one glance, then Start (or a sample on devices without LiDAR).
@MainActor
struct ScanIntroView: View {
    let isSupported: Bool
    let onStart: () -> Void
    let onSample: () -> Void
    let onTips: () -> Void

    private static let tips = [
        "Ask someone to hold the phone.",
        "Stand barefoot on a plain floor.",
        "Two slow laps around your foot.",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                Text("Scan your foot")
                    .display(.hero)
                    .accessibilityAddTraits(.isHeader)
                    .reveal(0)
                PositioningDiagram()
                    .reveal(1)
                VStack(spacing: 0) {
                    ForEach(Array(Self.tips.enumerated()), id: \.offset) { index, tip in
                        if index > 0 { Hairline() }
                        Text(tip)
                            .foregroundStyle(.ink2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, Space.md)
                    }
                }
                .reveal(2)
            }
            .padding(.horizontal, Space.page)
            .padding(.top, Space.lg)
        }
        .safeAreaInset(edge: .bottom) { actions.reveal(3) }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: Space.sm) {
            if isSupported {
                Button("Start scan", action: onStart)
                    .buttonStyle(.archyPrimary)
                    .accessibilityIdentifier("scan.start")
                HStack {
                    Button("How to scan", action: onTips)
                    Button("View a sample", action: onSample)
                        .accessibilityIdentifier("scan.sample")
                }
                .buttonStyle(.archyGhost)
            } else {
                Text("Scanning needs an iPhone with LiDAR.")
                    .font(.callout)
                    .foregroundStyle(.inkSecondary)
                Button("View a sample scan", action: onSample)
                    .buttonStyle(.archyPrimary)
                    .accessibilityIdentifier("scan.sample")
                Button("How to scan", action: onTips)
                    .buttonStyle(.archyGhost)
            }
        }
        .padding(.horizontal, Space.page)
        .padding(.bottom, Space.sm)
        .frame(maxWidth: .infinity)
        .background(Color.bg)
    }
}
