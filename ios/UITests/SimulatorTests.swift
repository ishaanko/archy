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
    func testPremiumCoachControls() {
        finishSimpleQuiz()
        app.tabBars.buttons["Premium"].tap()
        XCTAssertTrue(app.buttons["premium.exercises"].waitForExistence(timeout: 5))
        capture("13-Premium-home")
        app.buttons["premium.exercises"].tap()
        XCTAssertTrue(app.buttons["studio.shortFoot"].waitForExistence(timeout: 4))
        capture("14-Movement-studio")
        app.buttons["studio.shortFoot"].tap()
        XCTAssertTrue(app.navigationBars["Exercise coach"].waitForExistence(timeout: 4))
        capture("15-Short-foot-technique")
        tapChoice("coach.next")
        capture("26-Guided-practice-diagram")
        tapChoice("coach.start")
        XCTAssertTrue(app.buttons["coach.pause"].waitForExistence(timeout: 3))
        app.buttons["coach.pause"].tap()
        XCTAssertTrue(app.staticTexts["Paused"].exists)
        capture("16-Coach-paused")
        app.buttons["coach.reset"].tap()
        XCTAssertTrue(app.buttons["coach.start"].exists)
        XCTAssertFalse(app.staticTexts["Paused"].exists)
        app.buttons["coach.start"].tap()
        XCTAssertTrue(app.staticTexts["Relax"].waitForExistence(timeout: 8))
        capture("17-Coach-relax-phase")
        app.navigationBars.buttons["Movement studio"].tap()
        tapChoice("studio.balance")
        XCTAssertTrue(app.navigationBars["Balance coach"].waitForExistence(timeout: 4))
        tapChoice("coach.balance.start")
        app.buttons["coach.balance.pause"].tap()
        XCTAssertTrue(app.staticTexts["Paused"].exists)
        capture("18-Supported-balance")
        app.buttons["coach.balance.reset"].tap()
        XCTAssertTrue(app.buttons["coach.balance.start"].exists)
    }
    func testPremiumRequestConsentAndPersistence() {
        finishSimpleQuiz()
        app.tabBars.buttons["Premium"].tap()
        tapChoice("premium.spaceInsole")
        XCTAssertTrue(app.navigationBars["Insole request"].waitForExistence(timeout: 4))
        app.switches["request.example"].tap()
        capture("19-Request-sample-data")
        tapChoice("scan.choose")
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        capture("29-Scan-file-picker")
        app.buttons["Cancel"].tap()
        let consent = app.switches["request.consent"]
        for _ in 0..<12 where !consent.isHittable { app.swipeUp() }
        XCTAssertTrue(consent.isHittable)
        XCTAssertFalse(app.buttons["request.prepare"].isEnabled)
        consent.tap()
        tapChoice("request.prepare")
        XCTAssertTrue(app.staticTexts["Draft saved · not sent"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["request.share"].exists)
        capture("20-Consent-and-local-draft")
        consent.tap()
        XCTAssertFalse(app.buttons["request.share"].exists)
        app.terminate()
        app.launchArguments = []
        app.launch()
        app.tabBars.buttons["Premium"].tap()
        tapChoice("premium.requests")
        XCTAssertTrue(app.staticTexts["Demo draft · not sent"].firstMatch.waitForExistence(timeout: 5))
        capture("21-Saved-request-history")
    }
    func testSpaceEnvironmentReachesInsoleRequest() {
        finishSimpleQuiz()
        app.tabBars.buttons["Space"].tap()
        let explorer = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Biomechanics Explorer")).firstMatch
        for _ in 0..<4 where !explorer.isHittable { app.swipeUp() }
        explorer.tap()
        tapChoice("gravity.Moon")
        app.tabBars.buttons["Premium"].tap()
        tapChoice("premium.spaceInsole")
        app.switches["request.example"].tap()
        for _ in 0..<5 where !app.staticTexts["0.165 g · Space Insole concept"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["0.165 g · Space Insole concept"].exists)
        XCTAssertTrue(app.staticTexts["Retention + adjustable cushioning"].exists)
        capture("22-Moon-insole-concept")
        // A new environment requires fresh consent; no data is silently shared.
        let consent = app.switches["request.consent"]
        for _ in 0..<10 where !consent.isHittable { app.swipeUp() }
        XCTAssertEqual(consent.value as? String, "0")
        XCTAssertFalse(app.buttons["request.prepare"].isEnabled)
        consent.tap()
        let right = app.segmentedControls.buttons["Right"]
        for _ in 0..<14 where !right.isHittable { app.swipeDown() }
        XCTAssertTrue(right.isHittable)
        right.tap()
        for _ in 0..<14 where !consent.isHittable { app.swipeUp() }
        XCTAssertEqual(consent.value as? String, "0")
        XCTAssertFalse(app.buttons["request.prepare"].isEnabled)
    }
    func testPremiumLargeTextAndFreeAccessibility() {
        finishSimpleQuiz()
        app.terminate()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-accessibility.voiceGuidance", "NO"]
        app.launch()
        app.tabBars.buttons["Premium"].tap()
        capture("23-Large-text-premium")
        tapChoice("premium.exercises")
        tapChoice("studio.balance")
        tapChoice("coach.balance.start")
        app.buttons["coach.balance.pause"].tap()
        XCTAssertTrue(app.staticTexts["Paused"].exists)
        capture("24-Large-text-balance-controls")
        app.tabBars.buttons["Today"].tap()
        app.buttons["Accessibility settings"].tap()
        let cues = app.switches["Audio cues"]
        for _ in 0..<10 where !cues.isHittable { app.swipeUp() }
        XCTAssertTrue(cues.isHittable)
        capture("25-Free-accessibility-and-voice")
        let grok = app.switches["settings.grok"]
        for _ in 0..<10 where !grok.exists { app.swipeUp() }
        XCTAssertTrue(grok.exists)
        XCTAssertFalse(grok.isEnabled)
        capture("25-Free-accessibility-and-voice")
    }
    func testVoiceConfigurationAndOfflineFallback() {
        app.buttons["Accessibility settings"].tap()
        tapChoiceByLabel("Remove connection")
        let url = app.textFields["settings.proxyURL"]
        for _ in 0..<10 where !url.isHittable { app.swipeUp() }
        url.tap()
        url.typeText("https://127.0.0.1:1/narrate")
        app.buttons["settings.keyboardDone"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let token = app.secureTextFields["settings.proxyToken"]
        for _ in 0..<4 where !token.isHittable { app.swipeUp() }
        token.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        token.typeText("qa-only-proxy-token-not-a-real-secret")
        app.buttons["settings.keyboardDone"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        tapChoiceByLabel("Save connection")
        capture("28-Voice-connection-saved")
        XCTAssertFalse(app.staticTexts["The service token could not be saved in Keychain."].exists)
        XCTAssertFalse(app.staticTexts["Enter an HTTPS /narrate URL and a service token of at least 24 characters."].exists)
        let grok = app.switches["settings.grok"]
        for _ in 0..<10 where !grok.isHittable { app.swipeDown() }
        XCTAssertTrue(grok.isEnabled)
        grok.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(grok.value as? String, "1")
        tapChoiceByLabel("Try voice instructions")
        app.swipeUp()
        let fallbackAppeared = app.staticTexts["Grok unavailable · using on-device narration"].waitForExistence(timeout: 10)
        capture("27-Voice-offline-fallback")
        XCTAssertTrue(fallbackAppeared)
        tapChoiceByLabel("Remove connection")
        for _ in 0..<10 where !grok.exists { app.swipeDown() }
        XCTAssertFalse(grok.isEnabled)
    }
    private func tapChoiceByLabel(_ label: String) {
        let element = app.buttons[label]
        for _ in 0..<12 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
        element.tap()
    }
    private func tapChoice(_ identifier: String) {
        let choice = app.buttons[identifier]
        for _ in 0..<14 where !choice.isHittable { app.swipeUp() }
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
