import SwiftUI

/// Home tab entry point. Owns its NavigationStack.
struct HomeTab: View {
    @Environment(AppRouter.self) private var router
    @Environment(OnboardingStore.self) private var onboarding
    @State private var editingAnswers = false
    var body: some View {
        NavigationStack {
            TodayView(onAdd: { router.tab = .scan }, onSpace: { router.tab = .insole }, onQuiz: { editingAnswers = true })
        }
        .sheet(isPresented: $editingAnswers) {
            OnboardingView(initial: onboarding.completed?.answers ?? OnboardingAnswers(), onCancel: { editingAnswers = false }) { answers in
                if onboarding.complete(answers) { editingAnswers = false }
            }
        }
    }
}

private struct TodayView: View {
    @Environment(OnboardingStore.self) private var onboarding
    @EnvironmentObject private var assessments: AssessmentStore
    let onAdd: () -> Void
    let onSpace: () -> Void
    let onQuiz: () -> Void
    @State private var accessibility = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ArchyWordmark()
                Eyebrow(text: "Your personal starting point")
                Text("Your foundation,\nin focus.").font(.largeTitle.weight(.medium)).tracking(-0.8)
                Text("One thoughtful step at a time. Add an assessment, then explore what your measurements describe.").foregroundStyle(.secondary)
                Panel {
                    HStack { Image(systemName: "plus.circle.fill").font(.title).foregroundStyle(Color.journeyAccent); Spacer(); Text("START HERE").font(.caption.weight(.semibold)).foregroundStyle(Color.journeyAccent) }
                    Text("Meet your feet.").font(.title2.weight(.medium))
                    Text("Choose guided photos or manual measurements in the + tab.").foregroundStyle(.secondary)
                    Button(action: onAdd) { Label("Add an assessment", systemImage: "arrow.right").frame(maxWidth: .infinity).frame(minHeight: 40) }.buttonStyle(ArchyPrimaryButtonStyle())
                }
                if let profile = onboarding.completed {
                    Panel {
                        HStack { Text("Your quiz").font(.headline); Spacer(); Button("Edit", action: onQuiz).accessibilityLabel("Edit quiz answers") }
                        Text(profile.answers.goal?.title ?? "Your starting point").font(.title3.weight(.semibold))
                        HStack(alignment: .top, spacing: 18) {
                            Label(profile.answers.focus.title, systemImage: "shoeprints.fill")
                            if let pain = profile.answers.pain?.score { Label("Pain \(pain)/10", systemImage: "heart.text.square") }
                        }.font(.callout).foregroundStyle(.secondary)
                        Text("Self-reported preferences · Saved on this iPhone").font(.caption).foregroundStyle(.secondary)
                    }
                }
                NavigationLink { MeasurementHome() } label: {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath").font(.title2)
                        VStack(alignment: .leading, spacing: 4) { Text("Your assessments").font(.headline); Text(assessments.records.isEmpty ? "Start your first measurement record" : "\(assessments.records.count) saved on this iPhone").font(.caption).foregroundStyle(.secondary) }
                        Spacer(); Image(systemName: "chevron.right")
                    }.padding(20).background(Color.archyCard, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
                Button(action: onSpace) {
                    HStack(spacing: 16) {
                        Image(systemName: "sparkles").font(.title).foregroundStyle(Color.lunar)
                        VStack(alignment: .leading, spacing: 5) { Text("Take a different perspective").font(.headline); Text("Biomechanics, AstroFit and real research.").font(.callout).foregroundStyle(Color.archySecondary) }
                        Spacer(); Image(systemName: "arrow.up.right")
                    }.foregroundStyle(Color.archyForeground).padding(22).background(Color.archyCard, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
            }.padding(24)
        }.background(Color.journeyBackground).navigationTitle("Today").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { accessibility = true } label: { Image(systemName: "accessibility") }.accessibilityLabel("Accessibility settings") } }
            .sheet(isPresented: $accessibility) { GuidanceSettingsView() }
    }
}
