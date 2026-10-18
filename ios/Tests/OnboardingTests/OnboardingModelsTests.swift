import Foundation
import Testing
@testable import OnboardingCore

struct OnboardingModelsTests {
    private var completeAnswers: OnboardingAnswers {
        OnboardingAnswers(goal: .understandArch, diagnosis: ReportedDiagnosis.none, pain: .noPain)
    }

    @Test func defaultsRequireAnswers() {
        let answers = OnboardingAnswers()
        #expect(answers.goal == nil)
        #expect(answers.diagnosis == nil)
        #expect(answers.pain == nil)
        #expect(answers.focus == .both)
        #expect(!answers.isComplete)
    }

    @Test func eachRequiredAnswerMustBePresent() {
        var answers = completeAnswers
        #expect(answers.isComplete)
        answers.goal = nil
        #expect(!answers.isComplete)
        answers = completeAnswers
        answers.diagnosis = nil
        #expect(!answers.isComplete)
        answers = completeAnswers
        answers.pain = nil
        #expect(!answers.isComplete)
    }

    @Test(arguments: [1, 2, 5, 9, 10])
    func validRatingsCompleteOnboarding(score: Int) {
        var answers = completeAnswers
        answers.pain = .rating(score)
        #expect(answers.isComplete)
        #expect(answers.pain?.score == score)
    }

    @Test(arguments: [Int.min, -1, 0, 11, Int.max])
    func invalidRatingsPreventCompletion(score: Int) {
        var answers = completeAnswers
        answers.pain = .rating(score)
        #expect(!answers.isComplete)
        #expect(throws: OnboardingValidationError.incomplete) {
            try CompletedOnboarding(answers: answers, completedAt: Date(timeIntervalSince1970: 0))
        }
    }

    @Test func privateAnswersAreValidAndPreserved() throws {
        let answers = OnboardingAnswers(goal: .easePain, diagnosis: .preferNotToSay, pain: .preferNotToSay)
        #expect(answers.isComplete)
        #expect(answers.pain?.score == nil)
        #expect(PainResponse.noPain.score == 0)
        #expect(answers.pain != .noPain)
        let restored = try JSONDecoder().decode(OnboardingAnswers.self, from: JSONEncoder().encode(answers))
        #expect(restored == answers)
        #expect(restored.pain == .preferNotToSay)
        #expect(restored.pain?.score == nil)
    }

    @Test func completedAnswersRoundTrip() throws {
        let completed = try CompletedOnboarding(answers: completeAnswers, completedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let restored = try JSONDecoder().decode(CompletedOnboarding.self, from: JSONEncoder().encode(completed))
        #expect(restored == completed)
    }

    @Test func incompleteAnswersCannotBeCompleted() {
        #expect(throws: OnboardingValidationError.incomplete) {
            try CompletedOnboarding(answers: OnboardingAnswers(), completedAt: Date(timeIntervalSince1970: 0))
        }
    }
}
