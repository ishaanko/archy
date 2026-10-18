import SwiftUI

private enum Step: Int {
    case welcome, goal, background, pain, done

    var heading: String {
        switch self {
        case .welcome: "Check your arch. Print your insole."
        case .goal: "What brings you here?"
        case .background: "About your feet"
        case .pain: "Any pain today?"
        case .done: "You're set"
        }
    }

    /// How many progress segments are filled on this step.
    var progress: Int { min(max(rawValue, 0), 3) }
}

/// First run: welcome, three one-tap questions, then a finish moment. Also the Home "edit answers" sheet
/// (`onCancel != nil`), which skips the welcome and finish and saves right after the last question.
/// Debug routes (need `-ArchyFreshInstall YES`): onboarding.welcome|goal|background|pain|done, settings.
struct OnboardingView: View {
    var initial = OnboardingAnswers()
    var onCancel: (() -> Void)? = nil
    let onComplete: (OnboardingAnswers) -> Void

    @State private var answers: OnboardingAnswers
    @State private var step: Step
    @State private var painDraft = 5
    @State private var locked = false
    @State private var advanceTask: Task<Void, Never>?
    @State private var showsSettings = false
    @State private var voice = GuidanceVoice()
    @State private var routed = false
    @AppStorage("accessibility.voiceGuidance") private var automaticNarration = false
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var numberHeight = 190.0

    init(initial: OnboardingAnswers = OnboardingAnswers(), onCancel: (() -> Void)? = nil, onComplete: @escaping (OnboardingAnswers) -> Void) {
        self.initial = initial
        self.onCancel = onCancel
        self.onComplete = onComplete
        _answers = State(initialValue: initial)
        _step = State(initialValue: onCancel == nil ? .welcome : .goal)
        if case .rating(let score) = initial.pain { _painDraft = State(initialValue: score) }
    }

    private var isEditing: Bool { onCancel != nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                content.id(step).transition(.step)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(Motion.smooth.reduced(reduceMotion), value: step)
        .archyScreen()
        .sheet(isPresented: $showsSettings) { GuidanceSettingsView().presentationDetents([.medium, .large]) }
        .sensoryFeedback(.selection, trigger: answers)
        .sensoryFeedback(.success, trigger: step) { _, new in new == .done }
        .onChange(of: step) { _, new in
            if automaticNarration { voice.read(spoken(for: new)) } else { voice.stop() }
            UIAccessibility.post(notification: .screenChanged, argument: new.heading)
        }
        .onAppear {
            applyDebugRoute()
            if automaticNarration { voice.read(spoken(for: step)) }
        }
        .onDisappear { advanceTask?.cancel(); voice.stop() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Space.sm) {
            leadingButton.frame(width: 72, alignment: .leading)
            SegmentedProgress(filled: step.progress)
                .opacity(step == .welcome ? 0 : 1)
            Menu {
                Button("Read this step", systemImage: "speaker.wave.2") { voice.read(spoken(for: step)) }
                Button("Stop reading", systemImage: "stop.circle") { voice.stop() }
                Button("Accessibility settings", systemImage: "accessibility") { showsSettings = true }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.inkSecondary)
                    .frame(width: 72, height: 44, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Read aloud and accessibility")
            .accessibilityIdentifier("onboarding.menu")
        }
        .padding(.horizontal, Space.page)
        .frame(minHeight: 44)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    @ViewBuilder private var leadingButton: some View {
        if step == .goal, let onCancel {
            Button("Close", action: onCancel).buttonStyle(.archyGhost)
        } else if step != .welcome {
            Button("Back", action: back).buttonStyle(.archyGhost).accessibilityIdentifier("quiz.back")
        }
    }

    // MARK: Steps

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome: welcome
        case .goal: goal
        case .background: background
        case .pain: pain
        case .done: done
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            Spacer()
            WelcomeLogo()
            Spacer()
            Text("Check your arch.\nPrint your insole.")
                .display(.hero)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .reveal(9)
            VStack(spacing: Space.md) {
                Button("Get started") { forward() }
                    .buttonStyle(.archyPrimary)
                    .accessibilityIdentifier("onboarding.start")
                Text("Private on this iPhone. No account.")
                    .font(.footnote)
                    .foregroundStyle(.inkTertiary)
                    .frame(maxWidth: .infinity)
            }
            .reveal(11)
        }
        .padding(.horizontal, Space.page)
        .padding(.bottom, Space.lg)
    }

    private var goal: some View {
        question(step.heading, advancing: answers.goal != nil) {
            VStack(spacing: Space.md) {
                ForEach(FootGoal.allCases) { option in
                    ChoiceRow(title: option.title, selected: answers.goal == option, dimmed: locked && answers.goal != option, minHeight: 48) {
                        pick { answers.goal = option }
                    }
                    .accessibilityIdentifier("quiz.goal.\(option.rawValue)")
                }
            }
        }
    }

    private var background: some View {
        question(step.heading, advancing: answers.diagnosis != nil) {
            VStack(alignment: .leading, spacing: Space.xl) {
                ArchySegmented(selection: $answers.focus, options: FootFocus.allCases, label: \.title)
                VStack(alignment: .leading, spacing: Space.md) {
                    Text("Any diagnosis from a clinician?")
                        .font(.subheadline)
                        .foregroundStyle(.inkSecondary)
                    ForEach(ReportedDiagnosis.allCases) { option in
                        ChoiceRow(title: option.title, selected: answers.diagnosis == option, dimmed: locked && answers.diagnosis != option) {
                            pick { answers.diagnosis = option }
                        }
                        .accessibilityIdentifier("quiz.diagnosis.\(option.rawValue)")
                    }
                }
            }
        }
    }

    private var pain: some View {
        question(step.heading, advancing: false) {
            VStack(alignment: .leading, spacing: Space.xl) {
                MetricText(value: Double(shownPain), style: .giant)
                    .frame(height: numberHeight, alignment: .leading)
                    .opacity(painIsRated || answers.pain == .noPain ? 1 : 0.25)
                    .animation(Motion.snappy.reduced(reduceMotion), value: painIsRated)
                    .accessibilityHidden(true)
                VStack(spacing: Space.sm) {
                    PainScale(level: ratedPain ?? painDraft, isSet: painIsRated) { value in
                        painDraft = value
                        answers.pain = .rating(value)
                    }
                    HStack {
                        Text("Mild")
                        Spacer()
                        Text("Severe")
                    }
                    .font(.footnote)
                    .foregroundStyle(.inkTertiary)
                    .accessibilityHidden(true)
                }
                HStack(spacing: Space.md) {
                    ChoiceRow(title: "No pain", selected: answers.pain == .noPain, dimmed: locked && answers.pain != .noPain, font: .body.weight(.medium)) {
                        pick { answers.pain = .noPain }
                    }
                    .accessibilityIdentifier("quiz.pain.none")
                    ChoiceRow(title: "Prefer not to say", selected: answers.pain == .preferNotToSay, dimmed: locked && answers.pain != .preferNotToSay, font: .body.weight(.medium)) {
                        pick { answers.pain = .preferNotToSay }
                    }
                    .accessibilityIdentifier("quiz.pain.skip")
                }
            }
        } footer: {
            if painIsRated && !locked {
                Button(isEditing ? "Save" : "Continue") { forward() }
                    .buttonStyle(.archyPrimary)
                    .accessibilityIdentifier("quiz.next")
                    .transition(.step)
            }
        }
        .animation(Motion.smooth.reduced(reduceMotion), value: painIsRated)
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            Spacer()
            DrawnCheck()
            Text("You're set")
                .display(.hero)
                .accessibilityAddTraits(.isHeader)
                .reveal(6)
            Spacer()
            Button("Scan your feet") { onComplete(answers) }
                .buttonStyle(.archyPrimary)
                .accessibilityIdentifier("onboarding.finish")
                .reveal(8)
        }
        .padding(.horizontal, Space.page)
        .padding(.bottom, Space.lg)
    }

    /// Shared question layout: heading on top, answers pinned low, and a bottom slot that holds
    /// a quiet "Next" when this step already has an answer (after Back, or when editing).
    private func question<Answers: View, Footer: View>(
        _ title: String,
        advancing hasAnswer: Bool,
        @ViewBuilder answersView: () -> Answers,
        @ViewBuilder footer: () -> Footer = { EmptyView() }
    ) -> some View {
        let stack = VStack(alignment: .leading, spacing: Space.xl) {
            Text(title)
                .display(.hero)
                .padding(.top, Space.lg)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.xl)
            answersView()
        }
        return VStack(spacing: Space.md) {
            ViewThatFits(in: .vertical) {
                stack
                ScrollView { stack }.scrollBounceBehavior(.basedOnSize)
            }
            ZStack(alignment: .trailing) {
                footer()
                if hasAnswer && !locked {
                    Button("Next") { forward() }
                        .buttonStyle(.archyGhost)
                        .accessibilityIdentifier("quiz.next")
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .trailing)
        }
        .padding(.horizontal, Space.page)
        .padding(.bottom, Space.lg)
    }

    // MARK: Flow

    private var ratedPain: Int? {
        if case .rating(let value) = answers.pain { return value }
        return nil
    }

    private var painIsRated: Bool { ratedPain != nil }

    /// The number on the pain step: the rating, 0 for no pain, otherwise the untouched draft.
    private var shownPain: Int {
        switch answers.pain {
        case .rating(let value): value
        case .noPain: 0
        case .preferNotToSay, nil: painDraft
        }
    }

    /// Records a single-choice answer with a playful pop, holds a beat so the choice reads, then moves on.
    private func pick(_ apply: () -> Void) {
        guard !locked else { return }
        withAnimation(Motion.playful.reduced(reduceMotion)) {
            apply()
            locked = true
        }
        advanceTask?.cancel()
        advanceTask = Task {
            try? await Task.sleep(for: .milliseconds(380))
            guard !Task.isCancelled else { return }
            forward()
        }
    }

    private func forward() {
        advanceTask?.cancel()
        locked = false
        if step == .pain && isEditing {
            onComplete(answers)
        } else if let next = Step(rawValue: step.rawValue + 1) {
            step = next
        }
    }

    private func back() {
        advanceTask?.cancel()
        locked = false
        if let previous = Step(rawValue: step.rawValue - 1) { step = previous }
    }

    private func spoken(for step: Step) -> String {
        switch step {
        case .welcome: "Check your arch. Print your insole. Select Get started."
        case .goal: step.heading + " " + FootGoal.allCases.map(\.title).joined(separator: ". ")
        case .background: step.heading + ". Choose both feet, left or right. Then pick any diagnosis: " + ReportedDiagnosis.allCases.map(\.title).joined(separator: ". ")
        case .pain: step.heading + " Adjust the scale from 1 to 10, or choose no pain, or prefer not to say."
        case .done: "You're set. Select Scan your feet."
        }
    }

    private func applyDebugRoute() {
        #if DEBUG
        guard !routed, !isEditing, let route = router.debugRoute else { return }
        routed = true
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            switch route {
            case "onboarding.goal": step = .goal
            case "onboarding.background": step = .background
            case "onboarding.pain": step = .pain
            case "onboarding.done":
                if !answers.isComplete { answers = OnboardingAnswers(goal: .understandArch, diagnosis: ReportedDiagnosis.none, pain: .rating(4)) }
                step = .done
            case "settings": showsSettings = true
            default: break
            }
        }
        #endif
    }
}
