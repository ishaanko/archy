import SwiftUI

private enum QuizStep: Int, CaseIterable {
    case goal, background, comfort, ready
    var title: String {
        switch self {
        case .goal: "What would you like to explore?"
        case .background: "A little about your feet."
        case .comfort: "How do your feet feel today?"
        case .ready: "Your next step starts here."
        }
    }
    var detail: String {
        switch self {
        case .goal: "A few quick questions will help shape your first visit."
        case .background: "Only share what you’re comfortable with."
        case .comfort: "This records your experience. It doesn’t assess or diagnose a condition."
        case .ready: "Choose photos or manual measurements in the + tab. You’re in control of what you add."
        }
    }
}

struct OnboardingView: View {
    var initial = OnboardingAnswers()
    var onCancel: (() -> Void)? = nil
    let onComplete: (OnboardingAnswers) -> Void
    @State private var answers = OnboardingAnswers()
    @State private var step: QuizStep = .goal
    @State private var painLevel = 4.0
    @State private var voice = GuidanceVoice()
    @State private var showsAccessibility = false
    @State private var initialized = false
    @AppStorage("accessibility.voiceGuidance") private var automaticNarration = false
    @AppStorage("accessibility.readingFriendly") private var readingFriendly = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        questionHeading.id("questionTop")
                        questionContent
                        if step != .ready {
                            Label("Your answers stay on this iPhone", systemImage: "lock.shield")
                                .font(.footnote).foregroundStyle(.secondary).padding(.top, 4)
                        }
                    }.padding(.horizontal, 24).padding(.bottom, 28)
                }.onChange(of: step) { _, _ in
                    proxy.scrollTo("questionTop", anchor: .top)
                    if automaticNarration { voice.read(spokenPrompt) } else { voice.stop() }
                    UIAccessibility.post(notification: .screenChanged, argument: step.title)
                }
            }
            footer
        }
        .background(Color.journeyBackground)
        .foregroundStyle(Color.archyForeground)
        .tint(.journeyAccent)
        .fontDesign(readingFriendly ? .rounded : .default)
        .lineSpacing(readingFriendly ? 6 : 2)
        .sheet(isPresented: $showsAccessibility) { GuidanceSettingsView().presentationDetents([.medium, .large]) }
        .onAppear {
            if !initialized {
                answers = initial
                if case .rating(let score) = initial.pain { painLevel = Double(score) }
                initialized = true
            }
            if automaticNarration { voice.read(spokenPrompt) }
        }
        .onDisappear { voice.stop() }
        .sensoryFeedback(.selection, trigger: step)
    }

    private var header: some View {
        VStack(spacing: 22) {
            HStack {
                ArchyWordmark()
                Spacer()
                Menu {
                    Button("Read this step", systemImage: "speaker.wave.2") { voice.read(spokenPrompt) }
                    Button("Stop reading", systemImage: "stop.circle") { voice.stop() }
                } label: { Image(systemName: "speaker.wave.2").frame(width: 44, height: 44) }
                .accessibilityLabel("Read-aloud controls")
                Button { showsAccessibility = true } label: { Image(systemName: "accessibility").frame(width: 44, height: 44) }.accessibilityLabel("Accessibility settings")
                if let onCancel { Button("Close", action: onCancel) }
            }
            HStack(spacing: 8) {
                ForEach(QuizStep.allCases, id: \.rawValue) { item in
                    Capsule().fill(item.rawValue <= step.rawValue ? Color.journeyAccent : Color.journeyAccent.opacity(0.13)).frame(height: 5)
                }
            }.accessibilityElement(children: .ignore).accessibilityLabel("Question \(step.rawValue + 1) of 4")
        }.padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 20)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var questionHeading: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(step == .ready ? "READY WHEN YOU ARE" : "GETTING TO KNOW YOU · \(step.rawValue + 1) OF 3")
                .font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(Color.journeyAccent)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            Text(step.title).font(.title.weight(.medium)).tracking(-0.7).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            Text(step.detail).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var questionContent: some View {
        switch step {
        case .goal:
            VStack(spacing: 12) {
                ForEach(FootGoal.allCases) { goal in
                    QuizChoice(title: goal.title, detail: goal.detail, icon: goal.icon, selected: answers.goal == goal) { answers.goal = goal }
                        .accessibilityIdentifier("quiz.goal.\(goal.rawValue)")
                }
            }
        case .background:
            VStack(alignment: .leading, spacing: 20) {
                Text("Has a clinician diagnosed a foot condition?").font(.headline)
                VStack(spacing: 10) {
                    ForEach(ReportedDiagnosis.allCases) { diagnosis in
                        QuizChoice(title: diagnosis.title, detail: diagnosis.detail, icon: nil, selected: answers.diagnosis == diagnosis) { answers.diagnosis = diagnosis }
                            .accessibilityIdentifier("quiz.diagnosis.\(diagnosis.rawValue)")
                    }
                }
                Text("Which foot would you like to focus on?").font(.headline)
                if typeSize.isAccessibilitySize {
                    Picker("Foot focus", selection: $answers.focus) {
                        ForEach(FootFocus.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.menu)
                } else {
                    Picker("Foot focus", selection: $answers.focus) {
                        ForEach(FootFocus.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                }
            }
        case .comfort:
            comfortQuestion
        case .ready:
            readySummary
        }
    }

    private var comfortQuestion: some View {
        VStack(spacing: 12) {
            QuizChoice(title: "No pain today", detail: "Record a pain level of 0.", icon: "face.smiling", selected: answers.pain == .noPain) { answers.pain = .noPain }.accessibilityIdentifier("quiz.pain.none")
            QuizChoice(title: "I’d like to record a pain level", detail: "Choose a number from 1 to 10.", icon: "slider.horizontal.3", selected: ratesPain) { answers.pain = .rating(Int(painLevel)) }.accessibilityIdentifier("quiz.pain.rating")
            if ratesPain {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(Int(painLevel))").font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit()
                        Text("/ 10").font(.title3).foregroundStyle(.secondary)
                        Spacer()
                        Text("Your reported level").font(.caption).foregroundStyle(.secondary)
                    }
                    Slider(value: $painLevel, in: 1...10, step: 1).accessibilityLabel("Pain level").accessibilityValue("\(Int(painLevel)) out of 10")
                    HStack { Text("1 · Very mild"); Spacer(); Text("10 · Worst imaginable") }.font(.caption).foregroundStyle(.secondary)
                }.padding(20).background(Color.archyCard, in: RoundedRectangle(cornerRadius: 12))
                    .onChange(of: painLevel) { _, value in answers.pain = .rating(Int(value)) }
            }
            QuizChoice(title: "Prefer not to say", detail: "Continue without a pain score.", icon: nil, selected: answers.pain == .preferNotToSay) { answers.pain = .preferNotToSay }.accessibilityIdentifier("quiz.pain.skip")
        }
    }

    private var readySummary: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 20) {
                Label("Your starting point", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(Color.journeyAccent)
                summaryRow("Goal", answers.goal?.title ?? "Not selected")
                summaryRow("Focus", answers.focus.title)
                summaryRow("Previous diagnosis", answers.diagnosis?.title ?? "Not shared")
                summaryRow("Pain today", answers.pain?.summary ?? "Not shared")
            }.padding(22).background(Color.archyCard, in: RoundedRectangle(cornerRadius: 12))
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "plus.circle.fill").font(.title).foregroundStyle(Color.journeyAccent)
                VStack(alignment: .leading, spacing: 6) {
                    Text("First, add your foundation").font(.headline)
                    Text("Add photos or measurements, then explore SpaceLab.").font(.callout).foregroundStyle(.secondary)
                }
            }
            Text("Personalized guidance, not a medical diagnosis.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button(action: advance) {
                Group {
                    if typeSize.isAccessibilitySize {
                        Text(step == .ready ? "Open +" : step == .comfort ? "Review" : "Next")
                            .frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true)
                    } else {
                        HStack { Text(step == .ready ? "Open the + tab" : step == .comfort ? "Review my starting point" : "Continue"); Spacer(); Image(systemName: step == .ready ? "plus" : "arrow.right") }
                    }
                }.font(.headline).padding(.horizontal, 20).frame(minHeight: 54)
            }.buttonStyle(ArchyPrimaryButtonStyle()).buttonBorderShape(.roundedRectangle(radius: 17)).disabled(!canContinue).accessibilityIdentifier("quiz.next").id(step)
            if step != .goal {
                Button("Back") { if let previous = QuizStep(rawValue: step.rawValue - 1) { step = previous } }
                    .font(.callout.weight(.semibold)).frame(minHeight: 36).accessibilityIdentifier("quiz.back")
            } else if !typeSize.isAccessibilitySize { Text("Private on this iPhone · No account needed").font(.caption).foregroundStyle(.secondary) }
        }.padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 10).background(.regularMaterial)
            .transaction { transaction in transaction.animation = nil; transaction.disablesAnimations = true }
    }

    private var ratesPain: Bool {
        guard let pain = answers.pain else { return false }
        if case .rating = pain { return true }
        return false
    }
    private var canContinue: Bool {
        switch step {
        case .goal: answers.goal != nil
        case .background: answers.diagnosis != nil
        case .comfort: answers.pain?.isValid == true
        case .ready: answers.isComplete
        }
    }
    private var spokenPrompt: String {
        let options: String = switch step {
        case .goal: FootGoal.allCases.map { $0.title + ". " + $0.detail }.joined(separator: ". ")
        case .background: "Has a clinician diagnosed a foot condition? " + ReportedDiagnosis.allCases.map(\.title).joined(separator: ". ")
        case .comfort: "Choose no pain, a pain rating from one to ten, or prefer not to say."
        case .ready: answers.summaryText + ". Select Open the plus tab to add photos or measurements."
        }
        return step.title + ". " + step.detail + ". " + options
    }
    private func advance() {
        guard canContinue else { return }
        if step == .ready { onComplete(answers) }
        else if let next = QuizStep(rawValue: step.rawValue + 1) {
            step = next
        }
    }
}

private struct QuizChoice: View {
    let title: String
    let detail: String
    let icon: String?
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                if let icon {
                    Image(systemName: icon).font(.title2).dynamicTypeSize(...DynamicTypeSize.xxxLarge).foregroundStyle(Color.journeyAccent)
                        .frame(width: 44, height: 48).background(Color.journeyAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline).foregroundStyle(Color.archyForeground).fixedSize(horizontal: false, vertical: true)
                    if !detail.isEmpty { Text(detail).font(.subheadline).foregroundStyle(Color.journeySecondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3).dynamicTypeSize(...DynamicTypeSize.xxxLarge).foregroundStyle(selected ? Color.journeyAccent : Color.secondary.opacity(0.4)).accessibilityHidden(true)
            }.padding(16).frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                .background(selected ? Color.journeyAccent.opacity(0.055) : Color.archyCard, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.journeyAccent : Color.archyBorder, lineWidth: selected ? 1.5 : 1))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

