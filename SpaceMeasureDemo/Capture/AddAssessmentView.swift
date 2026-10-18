import SwiftUI

struct AddAssessmentView: View {
    @Environment(OnboardingStore.self) private var onboarding
    @State private var showsAccessibility = false
    @State private var voice = GuidanceVoice()
    @AppStorage("accessibility.voiceGuidance") private var automaticNarration = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Label("YOUR NEXT STEP", systemImage: "plus.circle.fill").font(.caption.weight(.semibold)).tracking(1).foregroundStyle(Color.journeyAccent)
                Text("Let’s build your\nstarting picture.").font(.largeTitle.weight(.medium)).tracking(-0.7)
                Text("Choose the method that works for you. We’ll guide you, one step at a time.").foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.journeyAccent)
                    Text("Quiz complete").font(.callout.weight(.medium))
                    Spacer()
                    if let focus = onboarding.completed?.answers.focus { Text(focus.title).font(.caption).foregroundStyle(.secondary) }
                }.padding(15).background(Color.journeyAccent.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                NavigationLink { MeasurementHome() } label: {
                    methodCard(title: "Manual measurements", detail: "A tape measure, a ruler and a few minutes. Calculate AHI, navicular drop and foot proportions.", icon: "ruler", badge: "RESULTS AVAILABLE", cta: "Start measuring", color: .journeyAccent)
                }.buttonStyle(.plain).accessibilityIdentifier("add.measurements")
                NavigationLink { GuidedPhotosView() } label: {
                    methodCard(title: "Guided photos", detail: "Add inner-side, top and rear views of each foot. Follow clear framing instructions.", icon: "camera.viewfinder", badge: "LOCAL PHOTO SET", cta: "Add photos", color: .indigo)
                }.buttonStyle(.plain).accessibilityIdentifier("add.photos")
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "speaker.wave.2").foregroundStyle(Color.journeyAccent)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Guidance at your pace").font(.headline)
                        Text("On-device read-aloud is available now. Grok voice is not connected yet.").font(.callout).foregroundStyle(.secondary)
                        Button("Read these options") { voice.read("Choose manual measurements to calculate Arch Height Index, navicular drop and foot proportions. Or choose guided photos to collect inner-side, top and rear views of both feet. Photo analysis and Grok voice are not connected in this prototype.") }.font(.callout.weight(.semibold))
                    }
                }.padding(20).background(Color.archyCard, in: RoundedRectangle(cornerRadius: 12))
                Text("Manual measurements use Arch Height Index, not footprint Arch Index. Photos collected here are not automatically classified. All results are educational, not a medical diagnosis.").font(.footnote).foregroundStyle(.secondary)
            }.padding(24)
        }.background(Color.journeyBackground).navigationTitle("Add an assessment").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showsAccessibility = true } label: { Image(systemName: "accessibility") }.accessibilityLabel("Accessibility settings") } }
            .sheet(isPresented: $showsAccessibility) { GuidanceSettingsView() }
            .onAppear { if automaticNarration { voice.read("Your quiz is complete. You are in the plus tab. Choose manual measurements for a guided tape-measure assessment, or guided photos to collect views of each foot.") } }
            .onDisappear { voice.stop() }
    }
    private func methodCard(title: String, detail: String, icon: String, badge: String, cta: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: icon).font(.title).foregroundStyle(color).frame(width: 56, height: 56).background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                Spacer()
                Text(badge).font(.system(.caption2, design: .monospaced, weight: .semibold)).foregroundStyle(color).padding(.horizontal, 10).padding(.vertical, 7).background(color.opacity(0.07), in: Capsule())
            }
            Text(title).font(.title2.weight(.medium)).foregroundStyle(Color.ink)
            Text(detail).font(.callout).foregroundStyle(Color.journeySecondary).fixedSize(horizontal: false, vertical: true)
            HStack { Text(cta); Spacer(); Image(systemName: "arrow.right") }.font(.headline).foregroundStyle(color)
        }.padding(22).background(Color.archyCard, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.archyBorder))
    }
}
