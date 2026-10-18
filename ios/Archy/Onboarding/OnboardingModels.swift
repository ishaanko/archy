import Foundation

enum FootGoal: String, CaseIterable, Codable, Identifiable, Sendable {
    case understandArch
    case trackComfort
    case exploreSpace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .understandArch: "Understand my arch"
        case .trackComfort: "Track my comfort"
        case .exploreSpace: "Explore space biomechanics"
        }
    }

    var detail: String {
        switch self {
        case .understandArch: "Explore information about foot arches."
        case .trackComfort: "Keep a personal record of how your feet feel."
        case .exploreSpace: "Discover foot structure, gravity and space research."
        }
    }

    var icon: String {
        switch self {
        case .understandArch: "shoeprints.fill"
        case .trackComfort: "chart.xyaxis.line"
        case .exploreSpace: "sparkles"
        }
    }
}

enum ReportedDiagnosis: String, CaseIterable, Codable, Identifiable, Sendable {
    case none
    case flatFeet
    case other
    case preferNotToSay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "No diagnosis"
        case .flatFeet: "Flat feet"
        case .other: "Another diagnosis"
        case .preferNotToSay: "Prefer not to say"
        }
    }

    var detail: String {
        switch self {
        case .none: "I have not been diagnosed with a foot condition."
        case .flatFeet: "A healthcare professional has told me I have flat feet."
        case .other: "A healthcare professional has given me another foot diagnosis."
        case .preferNotToSay: "I would like to keep this private."
        }
    }
}

enum FootFocus: String, CaseIterable, Codable, Identifiable, Sendable {
    case both
    case left
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .both: "Both feet"
        case .left: "Left foot"
        case .right: "Right foot"
        }
    }
}

enum PainResponse: Codable, Equatable, Sendable {
    case noPain
    case rating(Int)
    case preferNotToSay

    var score: Int? {
        switch self {
        case .noPain: 0
        case .rating(let value): value
        case .preferNotToSay: nil
        }
    }

    var isValid: Bool {
        switch self {
        case .noPain, .preferNotToSay: true
        case .rating(let value): (1...10).contains(value)
        }
    }

    var summary: String {
        switch self {
        case .noPain: "You reported no pain."
        case .rating(let value) where (1...10).contains(value): "You reported pain at \(value) out of 10."
        case .rating: "Your pain rating is outside the 1–10 range."
        case .preferNotToSay: "You chose not to share a pain rating."
        }
    }
}

struct OnboardingAnswers: Codable, Equatable, Sendable {
    var goal: FootGoal? = nil
    var diagnosis: ReportedDiagnosis? = nil
    var pain: PainResponse? = nil
    var focus: FootFocus = .both

    var isComplete: Bool {
        goal != nil && diagnosis != nil && pain?.isValid == true
    }

    var summaryText: String {
        let goalSummary = goal.map { "Your goal: \($0.title)." } ?? "You have not selected a goal."
        let diagnosisSummary: String = switch diagnosis {
        case .some(.none): "You reported no prior foot diagnosis."
        case .flatFeet: "You reported a prior diagnosis of flat feet."
        case .other: "You reported another prior foot diagnosis."
        case .preferNotToSay: "You chose not to share your diagnosis history."
        case nil: "You have not answered the diagnosis question."
        }
        let painSummary = pain?.summary ?? "You have not answered the pain question."
        return "\(goalSummary) \(diagnosisSummary) \(painSummary) Your focus: \(focus.title). These are your self-reported answers."
    }

    var nextStepTitle: String {
        switch goal {
        case .understandArch: "Explore arch information"
        case .trackComfort: "Start your comfort journal"
        case .exploreSpace: "Explore space biomechanics"
        case nil: "Choose your goal"
        }
    }
}

enum OnboardingValidationError: Error, Equatable, Sendable {
    case incomplete
}

struct CompletedOnboarding: Codable, Equatable, Sendable {
    let answers: OnboardingAnswers
    let completedAt: Date

    init(answers: OnboardingAnswers, completedAt: Date) throws {
        guard answers.isComplete else {
            throw OnboardingValidationError.incomplete
        }
        self.answers = answers
        self.completedAt = completedAt
    }
}
