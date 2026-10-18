import Foundation
import Testing
@testable import OnboardingCore

struct OnboardingStoreTests {
    @Test @MainActor func answersPersistAcrossStoreInstances() throws {
        let domain = "OnboardingTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let answers = OnboardingAnswers(goal: .understandArch, diagnosis: .preferNotToSay, pain: .rating(5), focus: .right)
        let store = OnboardingStore(defaults: defaults)
        #expect(store.completed == nil)
        #expect(store.complete(answers))
        let restored = OnboardingStore(defaults: defaults)
        #expect(restored.completed?.answers == answers)
        #expect(restored.errorMessage == nil)
    }
    @Test @MainActor func incompleteEditsPreservePreviousAnswers() throws {
        let domain = "OnboardingTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = OnboardingStore(defaults: defaults)
        let answers = OnboardingAnswers(goal: .exploreSpace, diagnosis: ReportedDiagnosis.none, pain: .noPain)
        #expect(store.complete(answers))
        #expect(!store.complete(OnboardingAnswers()))
        #expect(store.completed?.answers == answers)
        #expect(OnboardingStore(defaults: defaults).completed?.answers == answers)
    }
    @Test @MainActor func malformedStoredAnswersReturnToQuiz() throws {
        let domain = "OnboardingTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(Data("invalid-json".utf8), forKey: "onboarding.completed.v1")
        let store = OnboardingStore(defaults: defaults)
        #expect(store.completed == nil)
        #expect(store.errorMessage != nil)
    }
}
