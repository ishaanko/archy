import XCTest

/// End-to-end walk through the app as a first-time user, attaching a screenshot of every screen.
/// Export the screenshots afterwards with `ios/scripts/e2e.sh`, which runs this and writes PNGs to `ios/e2e-artifacts/`.
@MainActor
final class ArchyFlowUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() async throws {
        continueAfterFailure = false
        app.launchArguments = ["-ArchyFreshInstall", "YES", "-accessibility.voiceGuidance", "NO"]
        app.launch()
    }

    func testFirstRunThroughEveryTab() {
        // Onboarding: welcome, three questions, finish. Single-choice answers advance on their own.
        tap("onboarding.start", shot: "01-welcome")
        tap("quiz.goal.understandArch", shot: "02-goal")
        tap("quiz.diagnosis.none", shot: "03-background")
        tap("quiz.pain.none", shot: "04-pain")
        tap("onboarding.finish", shot: "05-done")

        // Finishing lands on Scan. The Simulator has no LiDAR, so open the bundled sample scan.
        tap("scan.sample", shot: "06-scan-intro")
        XCTAssertTrue(app.buttons["scan.share"].waitForExistence(timeout: 15))
        sleep(2)
        capture("07-scan-sample")
        app.buttons["scan.new"].tap()

        // Home: try the example results, then start measuring by hand.
        tab("Home")
        tap("home.example", shot: "08-home-empty")
        XCTAssertTrue(app.buttons["results.insole"].waitForExistence(timeout: 5))
        sleep(1)
        capture("09-results")
        app.navigationBars.buttons.firstMatch.tap()
        tap("home.measure")
        let field = app.textFields["measure.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("260")
        capture("10-measure")
        app.navigationBars.buttons["BackButton"].tap() // leaving the wizard drops the keyboard off the tab bar

        // Insole studio: switch to Mars, open the request sheet.
        tab("Insole")
        tap("insole.env.mars", shot: "11-insole")
        sleep(1)
        capture("12-insole-mars")
        tap("insole.request")
        XCTAssertTrue(app.buttons["insole.save"].waitForExistence(timeout: 5))
        capture("13-insole-request")
        app.swipeDown(velocity: .fast)

        // Train: open the short-foot coach and start it.
        tab("Train")
        tap("studio.shortFoot", shot: "14-train")
        tap("coach.start", shot: "15-coach")
        sleep(5)
        capture("16-coach-running")
    }

    /// Live check of the Grok proxy: the debug launch arguments load the token from a file into the Keychain and
    /// enable Grok, then "Test voice" must report Grok rather than the on-device voice. Needs network and the token file.
    func testVoiceUsesGrokThroughLiveProxy() {
        app.terminate()
        app.launchArguments = [
            "-ArchyFreshInstall", "YES", "-accessibility.voiceGuidance", "NO", "-ArchyRoute", "settings",
            "-ArchyVoiceProxyURL", "https://tryarchy.vercel.app/api/narrate",
            "-ArchyVoiceTokenFile", "/Users/ishaanko/.config/archy/narration-proxy-token",
        ]
        app.launch()
        let test = app.buttons["settings.testVoice"]
        XCTAssertTrue(test.waitForExistence(timeout: 10), "Missing settings.testVoice")
        test.tap()
        // The row's label carries the live status: "Loading Grok voice", then "Grok voice" or a fallback message.
        let settled = NSPredicate(format: "label CONTAINS 'Grok voice' AND NOT label CONTAINS 'Loading' OR label CONTAINS 'on-device'")
        expectation(for: settled, evaluatedWith: test)
        waitForExpectations(timeout: 20)
        capture("voice-status")
        XCTAssertTrue(test.label.contains("Grok voice"), "Expected Grok, got: \(test.label)")
        XCTAssertFalse(test.label.contains("on-device"), "Fell back to on-device: \(test.label)")
    }

    /// Waits for a button, optionally screenshots the screen it's on, then taps it.
    private func tap(_ id: String, shot: String? = nil) {
        let button = app.buttons[id].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Missing \(id)")
        if let shot {
            sleep(1) // let entrance animations settle
            capture(shot)
        }
        button.tap()
    }

    private func tab(_ name: String) {
        let button = app.tabBars.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing tab \(name)")
        button.tap()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
