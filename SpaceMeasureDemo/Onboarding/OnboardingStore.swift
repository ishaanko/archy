import Foundation
import Observation
import OSLog

@MainActor @Observable
final class OnboardingStore {
    private(set) var completed: CompletedOnboarding?
    private(set) var errorMessage: String?
    private let defaults: UserDefaults
    private let key = "onboarding.completed.v1"
    private let logger = Logger(subsystem: "SpaceMeasureDemo", category: "Onboarding")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: key) else { return }
        do {
            let restored = try JSONDecoder().decode(CompletedOnboarding.self, from: data)
            guard restored.answers.isComplete else { throw OnboardingValidationError.incomplete }
            completed = restored
        }
        catch {
            errorMessage = "Your preferences could not be restored. You can take the quiz again."
            logger.error("Could not restore onboarding preferences")
        }
    }

    @discardableResult
    func complete(_ answers: OnboardingAnswers) -> Bool {
        do {
            let record = try CompletedOnboarding(answers: answers, completedAt: .now)
            let data = try JSONEncoder().encode(record)
            defaults.set(data, forKey: key)
            completed = record
            errorMessage = nil
            logger.info("Onboarding completed locally")
            return true
        } catch {
            errorMessage = "Finish each question before continuing."
            logger.error("Incomplete onboarding could not be saved")
            return false
        }
    }
}
