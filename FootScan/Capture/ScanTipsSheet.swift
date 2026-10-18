//
//  ScanTipsSheet.swift
//  FootScan
//

import SwiftUI

/// How to set up the scan: who holds the phone, how to stand, and the two laps.
@MainActor
struct ScanTipsSheet: View {
    let onStart: () -> Void

    private static let tips: [(symbol: String, text: String)] = [
        ("person.2.fill", "Have a friend hold the phone. You stand still."),
        ("figure.stand", "Barefoot, with trousers rolled above the ankle."),
        ("shoeprints.fill", "Weight on both feet, on a plain, non-shiny floor."),
        ("sun.max.fill", "Bright, even light."),
        ("arrow.triangle.2.circlepath", "Two slow laps: knee height, then near the floor."),
        ("timer", "Hold still for about 2 minutes."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Before You Scan")
                    .font(.title2.bold())
                PositioningDiagram()
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Self.tips, id: \.symbol) { tip in
                        HStack(spacing: 14) {
                            Image(systemName: tip.symbol)
                                .font(.title3)
                                .foregroundStyle(.tint)
                                .frame(width: 32)
                            Text(tip.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                onStart()
            } label: {
                Text("Got It")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .background(.bar)
        }
    }
}
