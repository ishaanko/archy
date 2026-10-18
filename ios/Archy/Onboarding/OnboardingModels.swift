import Foundation

/// What the user wants from archy. Each case maps to a tab: scan, insole, train.
enum FootGoal: String, CaseIterable, Codable, Identifiable, Sendable {
    case understandArch
    case customInsole
    case easePain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .understandArch: "Understand my arch"
        case .customInsole: "Get a custom insole"
        case .easePain: "Ease foot pain"
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
        case .none: "None"
        case .flatFeet: "Flat feet"
        case .other: "Something else"
        case .preferNotToSay: "Prefer not to say"
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
}

struct OnboardingAnswers: Codable, Equatable, Sendable {
    var goal: FootGoal? = nil
    var diagnosis: ReportedDiagnosis? = nil
    var pain: PainResponse? = nil
    var focus: FootFocus = .both

    var isComplete: Bool {
        goal != nil && diagnosis != nil && pain?.isValid == true
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
