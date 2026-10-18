import SwiftUI

/// Train tab entry point. Owns its NavigationStack.
struct TrainTab: View {
    var body: some View { NavigationStack { ExerciseLibraryView() } }
}

struct ExerciseLibraryView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Eyebrow(text: "Movement studio / Evidence-informed")
                Text("Meet your\nnext small step.").font(.largeTitle.weight(.medium)).tracking(-1)
                Text("Choose a lesson. Follow along at your pace.").foregroundStyle(Color.archySecondary)
                NavigationLink { ExerciseCoachView() } label: {
                    Panel {
                        Label("01 / Short-foot practice", systemImage: "shoeprints.fill").font(.title3.weight(.medium))
                        Text("Seated · 5 gentle repetitions").font(.caption.monospaced()).foregroundStyle(Color.archyAccent)
                        FootArchShape(height: 0.5).fill(Color.archyAccent.opacity(0.18)).overlay(FootArchShape(height: 0.5).stroke(Color.archyAccent, lineWidth: 2)).frame(height: 100).accessibilityHidden(true)
                        Text("Learn a subtle arch lift while keeping your heel and toes relaxed.").foregroundStyle(Color.archySecondary)
                        Label("Learn the movement", systemImage: "arrow.right")
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("studio.shortFoot")
                NavigationLink { BalanceCoachView() } label: {
                    Panel {
                        Label("02 / Supported balance", systemImage: "figure.stand").font(.title3.weight(.medium))
                        Text("Standing · 2 supported holds").font(.caption.monospaced()).foregroundStyle(Color.archyAccent)
                        Text("Heel-to-toe balance with counter support. Prefer sitting? Try short-foot practice.").foregroundStyle(Color.archySecondary)
                        Label("Start balance practice", systemImage: "arrow.right")
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("studio.balance")
                Text("Introductory lessons, not a personalized treatment plan. Research is included in each lesson.").font(.footnote).foregroundStyle(Color.archySecondary)
            }.padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.background(Color.archyBackground).navigationTitle("Movement studio").navigationBarTitleDisplayMode(.inline)
    }
}
