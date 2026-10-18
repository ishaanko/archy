import SwiftUI
import AudioToolbox

@MainActor
struct ExerciseCoachView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize
    @AppStorage("accessibility.voiceGuidance") private var automaticNarration = false
    @AppStorage("accessibility.audioCues") private var audioCues = false
    @State private var voice = GuidanceVoice()
    @State private var session = ShortFootSession()
    @State private var hasStarted = false
    @State private var isRunning = false
    @State private var lesson = true
    @State private var phaseBegan = Date()
    @State private var showsAccessibility = false

    private var title: String {
        if session.phase == .complete { return "Practice complete" }
        if !hasStarted { return "Find your short foot" }
        return session.phase == .hold ? "Gently lift your arch" : "Let your foot relax"
    }
    private var instruction: String {
        session.phase == .hold
            ? "Draw the base of your big toe gently toward your heel. Keep both planted, toes long, and breathe."
            : "Release the effort. Let your arch settle and keep your toes soft."
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Eyebrow(text: "Movement studio")
                    Spacer()
                    Text("SEATED · 1 MIN").font(.caption.monospaced()).foregroundStyle(Color.archySecondary)
                }
                Text("A little lift.\nA softer landing.")
                    .font(.largeTitle.weight(.semibold)).tracking(-1)
                Text("Practice a gentle arch lift.")
                    .foregroundStyle(Color.archySecondary)
                if lesson { technique.id("lesson") } else { practice.id("practice") }
                Panel {
                    Label("Keep it comfortable", systemImage: "heart")
                        .font(.headline)
                    Text("Use light effort. Stop for pain; seek care if it persists or worsens.")
                        .font(.subheadline).foregroundStyle(Color.archySecondary)
                }
                settings
                evidence
            }.padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(Color.archyBackground)
        .foregroundStyle(Color.archyForeground)
        .navigationTitle("Exercise coach")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { stop(); dismiss() } } }
        .task(id: isRunning) {
            guard isRunning else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard isRunning, scenePhase == .active else { return }
                let previous = session.phase
                session.tick()
                if session.phase != previous { phaseBegan = .now; announcePhase() }
                if session.phase == .complete { isRunning = false; return }
            }
        }
        .onChange(of: scenePhase) { _, value in if value != .active { stop() } }
        .onChange(of: automaticNarration) { _, enabled in if !enabled { voice.stop() } }
        .onDisappear { stop() }
        .sheet(isPresented: $showsAccessibility) { GuidanceSettingsView() }
        .onChange(of: lesson) { _, value in proxy.scrollTo(value ? "lesson" : "practice", anchor: .top) }
        }
    }

    private var technique: some View {
        Panel {
            Eyebrow(text: "01 / Learn the movement")
            CoachFootDiagram(lift: 0.6)
            Text("Small movement. Relaxed toes.").font(.title2.weight(.semibold))
            techniqueRow("1", "Sit comfortably", "Place your bare foot flat on the floor, with your knee above your ankle.")
            techniqueRow("2", "Make your foot a little shorter", "Gently draw your forefoot toward your heel to lift the arch. Keep your heel and big-toe base planted.")
            techniqueRow("3", "Keep your toes long", "Avoid curling or gripping your toes. Breathe normally, then fully release.")
            Button("Hear the technique") { voice.readScript("exercise.setup", fallback: "Sit with your foot flat. Gently draw the base of your big toe toward your heel. Keep both planted and your toes long. Then release.") }.frame(minHeight: 44)
            Button { lesson = false; if automaticNarration { voice.readScript("exercise.setup", fallback: "Sit comfortably with your foot flat. Gently draw the base of your big toe toward your heel, keep both planted and your toes long, then relax.") } } label: {
                Label("Try guided practice", systemImage: "arrow.right").frame(maxWidth: .infinity)
            }.buttonStyle(ArchyPrimaryButtonStyle()).accessibilityIdentifier("coach.next")
        }
    }

    private var practice: some View {
        Panel {
            HStack {
                Eyebrow(text: "02 / Guided practice")
                Spacer()
                Text("\(session.phase == .complete ? 5 : session.repetition) / 5")
                    .font(.headline.monospacedDigit()).foregroundStyle(Color.archyAccent)
                    .accessibilityLabel("Repetition \(session.repetition) of 5")
            }
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !isRunning || reduceMotion)) { context in
                CoachFootDiagram(lift: lift(at: context.date))
            }
            Text(title).font(.title2.weight(.semibold))
            if session.phase == .complete {
                Text("Take a moment to check how your feet feel.")
                    .foregroundStyle(Color.archySecondary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(!hasStarted ? "Ready" : session.phase == .hold ? "Hold" : "Relax")
                        .font(.title.weight(.medium)).foregroundStyle(Color.archyAccent)
                    if hasStarted {
                        Text("\(session.secondsRemaining)s").font(.title.monospacedDigit())
                        if !isRunning { Text("Paused").font(.caption.weight(.semibold)) }
                    }
                }.accessibilityElement(children: .combine)
                Text(!hasStarted ? "5 reps · hold 5s · relax 5s" : instruction)
                    .foregroundStyle(Color.archySecondary)
            }
            ProgressView(value: Double(session.elapsed), total: 50).tint(Color.archyAccent)
                .accessibilityLabel("Practice progress")
            if session.phase != .complete {
                Button {
                    if isRunning { stop() } else {
                        hasStarted = true
                        isRunning = true
                        phaseBegan = .now
                        announcePhase()
                    }
                } label: {
                    Label(isRunning ? "Pause practice" : hasStarted ? "Resume practice" : "Begin practice", systemImage: isRunning ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(ArchyPrimaryButtonStyle())
                    .id(isRunning ? "running" : hasStarted ? "paused" : "ready")
                    .accessibilityIdentifier(isRunning ? "coach.pause" : "coach.start")
            }
            footerLayout {
                Button("Reset") { stop(); session = ShortFootSession(); hasStarted = false }
                    .accessibilityIdentifier("coach.reset")
                if !textSize.isAccessibilitySize { Spacer() }
                Button(session.phase == .complete ? "Done" : "Review technique") {
                    stop()
                    if session.phase == .complete { dismiss() } else { lesson = true }
                }.accessibilityIdentifier("coach.next")
            }.font(.subheadline.weight(.medium)).tint(Color.archyForeground)
            Text("Introductory practice, not the full study program.")
                .font(.caption).foregroundStyle(Color.archySecondary)
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Read phase guidance aloud", isOn: $automaticNarration)
            Text(voice.status).font(.caption).foregroundStyle(Color.archySecondary)
            Button { stop(); showsAccessibility = true } label: { Label("Voice & accessibility settings", systemImage: "accessibility") }.frame(minHeight: 44)
            Toggle("Play phase-change cues", isOn: $audioCues)
        }.font(.subheadline).tint(Color.archyAccent)
    }

    private var evidence: some View {
        DisclosureGroup("What supports this movement?") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Small trials suggest short-foot exercise may help some people with flexible flat feet. Results are limited and do not promise a cure.")
                Text("One trial of 40 adults with symptomatic flexible flat feet studied 6 weeks of daily exercise (3 sets of 10) plus insoles, and found better pain and function outcomes than insoles alone.")
                Link("Read the 40-person trial ↗", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/36988565/")!)
                Text("Another trial of 45 people studied 6 weeks of daily short-foot exercise, with or without lower-extremity training, and reported improvements in dynamic gait function.")
                Link("Read the 45-person trial ↗", destination: URL(string: "https://pubmed.ncbi.nlm.nih.gov/37379736/")!)
            }.font(.footnote).foregroundStyle(Color.archySecondary).padding(.top, 10)
        }.font(.subheadline.weight(.medium)).tint(Color.archyForeground)
    }

    private func techniqueRow(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(Color.archyAccent).padding(9)
                .background(Color.archyAccent.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(Color.archySecondary)
            }
        }
    }

    private func lift(at date: Date) -> Double {
        guard hasStarted, session.phase != .complete else { return 0 }
        let target = session.phase == .hold ? 1.0 : 0.0
        guard !reduceMotion, isRunning else { return target }
        let progress = min(max(date.timeIntervalSince(phaseBegan), 0) / 0.8, 1)
        let eased = progress * progress * (3 - 2 * progress)
        return session.phase == .hold ? eased : 1 - eased
    }

    private var footerLayout: AnyLayout {
        textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout())
    }
    private func stop() { isRunning = false; voice.stop() }
    private func announcePhase() {
        if audioCues { AudioServicesPlaySystemSound(1104) }
        guard automaticNarration else { return }
        if session.phase == .complete { voice.readScript("exercise.complete", fallback: "Practice complete. Check how your feet feel.") }
        else { voice.readScript(session.phase == .hold ? "exercise.hold" : "exercise.relax", fallback: session.phase == .hold ? "Hold gently. Keep your toes long and breathe." : "Relax your foot completely.") }
    }
}

private struct CoachFootDiagram: View {
    let lift: Double
    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let heel = width * 0.12
                let toe = width * (0.88 - 0.025 * lift)
                let base: CGFloat = 120
                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: 12, y: base + 5))
                        path.addLine(to: CGPoint(x: width - 12, y: base + 5))
                    }.stroke(Color.archyBorder, lineWidth: 2)
                    Path { path in
                        path.move(to: CGPoint(x: heel, y: base))
                        path.addCurve(to: CGPoint(x: heel + 22, y: 55), control1: CGPoint(x: heel - 22, y: 100), control2: CGPoint(x: heel - 5, y: 55))
                        path.addCurve(to: CGPoint(x: toe, y: base - 20), control1: CGPoint(x: width * 0.45, y: 38), control2: CGPoint(x: toe - 45, y: 95))
                        path.addQuadCurve(to: CGPoint(x: toe, y: base), control: CGPoint(x: toe + 27, y: base))
                        path.addCurve(to: CGPoint(x: heel, y: base), control1: CGPoint(x: width * 0.59, y: base - 10 - 26 * lift), control2: CGPoint(x: width * 0.39, y: base - 8 - 25 * lift))
                        path.closeSubpath()
                    }.fill(Color.archyAccent.opacity(0.14))
                    .overlay {
                        CoachSole(lift: lift).stroke(Color.archyAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    }
                    ForEach([heel, toe], id: \.self) { x in
                        Circle().fill(Color.archyAccent).frame(width: 8, height: 8).position(x: x, y: base)
                    }
                }
            }.frame(height: 145)
            Text("Heel planted      •      Big-toe base planted")
                .font(.caption).foregroundStyle(Color.archySecondary)
            Text("Side view · movement exaggerated for clarity")
                .font(.caption2).foregroundStyle(Color.archySecondary)
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel("Side-view foot diagram. Arch \(lift > 0.5 ? "raised" : "relaxed"), heel and big-toe base remain planted.")
    }
}

private struct CoachSole: Shape {
    let lift: Double
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.12, y: 120))
        path.addCurve(to: CGPoint(x: rect.width * (0.88 - 0.025 * lift), y: 120), control1: CGPoint(x: rect.width * 0.39, y: 112 - 25 * lift), control2: CGPoint(x: rect.width * 0.59, y: 110 - 26 * lift))
        return path
    }
}
