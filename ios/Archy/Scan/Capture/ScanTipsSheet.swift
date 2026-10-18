import SwiftUI

/// The full "How to scan" guide: the diagram and every setup tip, with read-aloud.
/// Opens from the intro and from the camera's "?".
@MainActor
struct ScanTipsSheet: View {
    let onDone: () -> Void
    @AppStorage("accessibility.voiceGuidance") private var narration = false
    @State private var voice = GuidanceVoice()

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
                HStack {
                    Text("How to scan")
                        .display(.title)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button(action: read) {
                        Image(systemName: "speaker.wave.2").font(.body.weight(.medium)).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.archyGhost)
                    .foregroundStyle(.inkSecondary)
                    .accessibilityLabel("Read aloud")
                    .accessibilityIdentifier("scan.tips.read")
                }
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
        .task { if narration { read() } }
        .onDisappear { voice.stop() }
    }

    private func read() {
        voice.readScript("scan.tips", fallback: "How to scan. " + Self.tips.joined(separator: " "))
    }
}
