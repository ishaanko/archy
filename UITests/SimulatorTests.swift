import XCTest

@MainActor
final class OnboardingUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Override only the read domain for this launch. Completing the quiz still
        // writes to the app's persistent domain, tested by relaunching without it.
        app.launchArguments = ["-onboarding.completed.v1", "", "-accessibility.voiceGuidance", "NO"]
        app.launch()
        XCTAssertTrue(app.staticTexts["What would you like to explore?"].waitForExistence(timeout: 10))
    }
    func testQuizHandoffAndPersistence() {
        XCTAssertFalse(app.buttons["quiz.next"].isEnabled)
        capture("01-Welcome-quiz")
        app.buttons["quiz.goal.trackComfort"].tap()
        next()
        app.buttons["quiz.diagnosis.flatFeet"].tap()
        app.segmentedControls.buttons["Right foot"].tap()
        capture("02-Prior-diagnosis")
        next()
        app.buttons["quiz.pain.rating"].tap()
        let slider = app.sliders["Pain level"]
        slider.adjust(toNormalizedSliderPosition: 0.45)
        capture("03-Pain-rating")
        app.buttons["quiz.back"].tap()
        XCTAssertTrue(app.buttons["quiz.diagnosis.flatFeet"].isSelected)
        next()
        XCTAssertTrue(app.buttons["quiz.pain.rating"].isSelected)
        next()
        XCTAssertTrue(app.staticTexts["Your next step starts here."].exists)
        capture("04-Quiz-review")
        next()
        XCTAssertTrue(app.buttons["add.measurements"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Add"].isSelected)
        capture("05-Plus-tab")
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.staticTexts["Your foundation,\nin focus."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["What would you like to explore?"].exists)
        capture("06-Returning-home")
    }
    func testPrivateAnswersAndEditing() {
        app.buttons["quiz.goal.understandArch"].tap(); next()
        tapChoice("quiz.diagnosis.preferNotToSay"); next()
        tapChoice("quiz.pain.skip"); next()
        XCTAssertTrue(app.staticTexts["You chose not to share a pain rating."].exists)
        XCTAssertFalse(app.staticTexts["Pain 0/10"].exists)
        next()
        app.tabBars.buttons["Today"].tap()
        app.buttons["Edit quiz answers"].tap()
        XCTAssertTrue(app.buttons["quiz.goal.understandArch"].isSelected)
        app.buttons["Close"].tap()
        XCTAssertTrue(app.tabBars.buttons["Today"].exists)
    }
    func testPhotoMeasurementAndSpaceRoutes() {
        finishSimpleQuiz()
        app.buttons["add.photos"].tap()
        XCTAssertTrue(app.navigationBars["Guided photos"].waitForExistence(timeout: 4))
        capture("07-Guided-photo-collection")
        app.buttons["photo.left.innerSide"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["add.measurements"].tap()
        XCTAssertTrue(app.buttons["Begin assessment"].waitForExistence(timeout: 4))
        app.tabBars.buttons["Space"].tap()
        XCTAssertTrue(app.staticTexts["SpaceLab"].waitForExistence(timeout: 4))
        capture("08-Space-tab")
        let explorer = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Biomechanics Explorer")).firstMatch
        for _ in 0..<4 where !explorer.isHittable { app.swipeUp() }
        explorer.tap()
        XCTAssertTrue(app.navigationBars["Biomechanics"].waitForExistence(timeout: 4))
        capture("09-Explorer-in-tab")
    }
    func testReadingPreferencesAndNarrationControl() {
        app.buttons["Accessibility settings"].tap()
        XCTAssertTrue(app.staticTexts["Grok voice is not connected"].exists)
        app.switches["Reading-friendly layout"].tap()
        app.buttons["Done"].tap()
        app.buttons["Read-aloud controls"].tap()
        app.buttons["Read this step"].tap()
        XCTAssertTrue(app.staticTexts["What would you like to explore?"].exists)
        capture("10-Reading-friendly-onboarding")
    }
    func testLargeTextCanCompleteQuiz() {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["What would you like to explore?"].waitForExistence(timeout: 5))
        capture("11-Large-text-quiz")
        let goal = app.buttons["quiz.goal.understandArch"]
        if !goal.isHittable { app.swipeUp() }
        goal.tap(); next()
        let diagnosis = app.buttons["quiz.diagnosis.preferNotToSay"]
        for _ in 0..<4 where !diagnosis.isHittable { app.swipeUp() }
        diagnosis.tap(); next()
        let skip = app.buttons["quiz.pain.skip"]
        for _ in 0..<4 where !skip.isHittable { app.swipeUp() }
        skip.tap(); next()
        XCTAssertTrue(app.buttons["quiz.next"].isHittable)
        capture("12-Large-text-review")
        next()
        XCTAssertTrue(app.tabBars.buttons["Add"].isSelected)
    }
    private func tapChoice(_ identifier: String) {
        let choice = app.buttons[identifier]
        for _ in 0..<5 where !choice.isHittable { app.swipeUp() }
        XCTAssertTrue(choice.isHittable)
        choice.tap()
    }
    private func next() { XCTAssertTrue(app.buttons["quiz.next"].isEnabled); app.buttons["quiz.next"].tap() }
    private func finishSimpleQuiz() {
        app.buttons["quiz.goal.exploreSpace"].tap(); next()
        app.buttons["quiz.diagnosis.none"].tap(); next()
        app.buttons["quiz.pain.none"].tap(); next(); next()
        XCTAssertTrue(app.buttons["add.measurements"].waitForExistence(timeout: 5))
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
