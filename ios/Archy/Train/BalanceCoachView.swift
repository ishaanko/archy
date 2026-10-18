import SwiftUI
import AudioToolbox

@MainActor
struct BalanceCoachView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize
    @AppStorage("accessibility.voiceGuidance") private var narration = false
    @AppStorage("accessibility.audioCues") private var audioCues = false
    @State private var voice = GuidanceVoice()
    @State private var elapsed = 0
    @State private var started = false
    @State private var running = false

    private var complete: Bool { elapsed >= 60 }
    private var resting: Bool { elapsed % 30 >= 20 }
    private var round: Int { min(elapsed / 30 + 1, 2) }
    private var remaining: Int { resting ? 30 - elapsed % 30 : 20 - elapsed % 30 }
    private var phaseKey: String { complete ? "balance.complete" : resting ? "balance.relax" : "balance.hold" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Eyebrow(text: "Movement studio / Standing")
                Text("Find your\nsteady moment.").font(.largeTitle.weight(.semibold)).tracking(-1)
                Text("Supported tandem balance").font(.title3).foregroundStyle(Color.archySecondary)
                Panel {
                    Eyebrow(text: "Set yourself up")
                    Label("A solid counter comes first", systemImage: "hand.raised.fill").font(.headline)
                    Text("Stand beside a solid counter on a stable floor. Keep light fingertip contact and look at a fixed point. Place one foot in front of the other, heel toward toe. Keep your toes relaxed.")
                    Text("Keep support throughout. If balance or vision makes this unsafe, choose seated practice or ask a clinician for help.")
                        .font(.subheadline).foregroundStyle(Color.archySecondary)
                    Button("Hear setup") { voice.readScript("balance.setup", fallback: "Stand beside a solid counter on a stable floor. Keep fingertip support. Place one foot ahead of the other, heel toward toe, and look at a fixed point. Stop if you feel unsteady.") }
                        .font(.subheadline.weight(.medium)).tint(Color.archyAccent)
                }
                Panel {
                    HStack {
                        Eyebrow(text: "Guided practice")
                        Spacer()
                        Text("\(round) / 2").font(.headline.monospacedDigit()).foregroundStyle(Color.archyAccent)
                            .accessibilityLabel("Round \(round) of 2")
                    }
                    diagram
                    Text(complete ? "Practice complete" : !started ? "Ready when you are" : resting ? "Rest with support" : "Hold with support")
                        .font(.title2.weight(.semibold))
                    if started && !complete {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(remaining)s").font(.largeTitle.monospacedDigit().weight(.medium)).foregroundStyle(Color.archyAccent)
                            if !running { Text("Paused").font(.caption.weight(.semibold)) }
                        }.accessibilityElement(children: .combine)
                    }
                    Text(complete ? "Take a moment to notice how you feel before moving away from your support." : !started ? "Two 20-second holds, with 10 seconds to rest after each. Change your leading foot for round two." : resting ? "Return to a comfortable stance. Keep your support.\(round == 1 ? " Change your leading foot for the next hold." : " Breathe and let your toes soften.")" : "\(round == 1 ? "Left" : "Right") foot leads. Keep fingertip contact, eyes on one point, and breathe normally.")
                        .foregroundStyle(Color.archySecondary)
                    ProgressView(value: Double(elapsed), total: 60).tint(Color.archyAccent)
                        .accessibilityLabel("Balance practice progress")
                    if !complete {
                        Button {
                            if running { stop() } else { started = true; running = true; announce() }
                        } label: {
                            Label(running ? "Pause practice" : started ? "Resume practice" : "Begin practice", systemImage: running ? "pause.fill" : "play.fill")
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(ArchyPrimaryButtonStyle())
                            .id(running ? "running" : started ? "paused" : "ready")
                    .accessibilityIdentifier(running ? "coach.balance.pause" : "coach.balance.start")
                    }
                    footerLayout {
                        Button("Reset") { stop(); elapsed = 0; started = false }
                            .accessibilityIdentifier("coach.balance.reset")
                        if !textSize.isAccessibilitySize { Spacer() }
                        Button("Done") { stop(); dismiss() }
                    }.font(.subheadline.weight(.medium)).tint(Color.archyForeground)
                    Text("Introductory practice, not the full study program.")
                        .font(.caption).foregroundStyle(Color.archySecondary)
                }
                Panel {
                    Label("Stay within your comfort", systemImage: "heart").font(.headline)
                    Text("Stop for pain, dizziness or unsteadiness. Keep eyes open on a stable floor. Seek guidance if symptoms persist.")
                        .font(.subheadline).foregroundStyle(Color.archySecondary)
                }
                Toggle("Read phase guidance aloud", isOn: $narration).tint(Color.archyAccent)
                Toggle("Play phase-change cues", isOn: $audioCues).tint(Color.archyAccent)
                DisclosureGroup("What supports this practice?") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("A small randomized trial of 32 participants with flat feet studied 18 sessions over 6 weeks. Sensorimotor training plus short-foot exercise improved static and dynamic balance compared with sensorimotor training alone.")
                        Text("The program included tandem stance on a fixed surface (3 sets of 30 seconds in week one), alongside other exercises. This brief supported practice is different; the study does not establish that tandem stance alone treats flat feet or guarantees a benefit.")
                        Link("Read the randomized trial ↗", destination: URL(string: "https://pmc.ncbi.nlm.nih.gov/articles/PMC8544541/")!)
                    }.font(.footnote).foregroundStyle(Color.archySecondary).padding(.top, 10)
                }.font(.subheadline.weight(.medium)).tint(Color.archyForeground)
            }.padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(Color.archyBackground).foregroundStyle(Color.archyForeground)
        .navigationTitle("Balance coach").navigationBarTitleDisplayMode(.inline)
        .task(id: running) {
            guard running else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard running, scenePhase == .active else { return }
                let previous = phaseKey
                elapsed = min(elapsed + 1, 60)
                if previous != phaseKey { announce() }
                if complete { running = false; return }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { stop() } }
        .onChange(of: narration) { _, enabled in if !enabled { voice.stop() } }
        .onDisappear { stop() }
    }

    private var diagram: some View {
        VStack(spacing: 12) {
            HStack(spacing: 24) {
                RoundedRectangle(cornerRadius: 8).fill(Color.archyForeground.opacity(0.12))
                    .frame(width: 24, height: 180)
                    .overlay(Image(systemName: "hand.point.up.left.fill").foregroundStyle(Color.archySecondary))
                ZStack {
                    InsoleShape().fill(Color.archyAccent.opacity(0.18))
                        .overlay(InsoleShape().stroke(Color.archyAccent, lineWidth: 2))
                        .frame(width: 45, height: 105).offset(x: -22, y: leadOffset(left: true))
                    InsoleShape().fill(Color.archyAccent.opacity(0.18))
                        .overlay(InsoleShape().stroke(Color.archyAccent, lineWidth: 2))
                        .frame(width: 45, height: 105).scaleEffect(x: -1, y: 1)
                        .offset(x: 22, y: leadOffset(left: false))
                }.frame(width: 120, height: 220)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: round)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: resting)
            }.frame(maxWidth: .infinity)
            Text("Top view · counter support · \(resting || complete ? "comfortable stance" : round == 1 ? "left foot leads" : "right foot leads")")
                .font(.caption).foregroundStyle(Color.archySecondary)
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel("Foot placement diagram beside a solid counter. \(resting || complete ? "Feet in a comfortable stance." : round == 1 ? "Left foot in front of right, heel toward toe." : "Right foot in front of left, heel toward toe.")")
    }

    private func leadOffset(left: Bool) -> CGFloat {
        guard !resting, !complete else { return 0 }
        return (left == (round == 1)) ? -50 : 50
    }
    private var footerLayout: AnyLayout {
        textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout())
    }
    private func stop() { running = false; voice.stop() }
    private func announce() {
        if audioCues { AudioServicesPlaySystemSound(1104) }
        guard narration else { return }
        voice.readScript(phaseKey, fallback: complete ? "Practice complete. Stay supported as you finish." : resting ? "Rest in a comfortable stance, keeping your support. Change your leading foot for the next hold." : "Hold with fingertip support. Keep your eyes on a fixed point and breathe.")
    }
}
