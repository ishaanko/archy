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

    func testOnboardingMenuStaysOnEveryStep() {
        let menu = app.buttons["onboarding.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "Missing menu on welcome")
        let welcomeFrame = menu.frame
        for (id, step) in [("onboarding.start", "goal"), ("quiz.goal.understandArch", "background"),
                           ("quiz.diagnosis.none", "pain"), ("quiz.pain.none", "done")] {
            tap(id)
            XCTAssertTrue(app.buttons["onboarding.finish"].exists || app.buttons["quiz.back"].waitForExistence(timeout: 5))
            sleep(1)
            capture("menu-\(step)")
            XCTAssertTrue(menu.exists && menu.isHittable, "Menu missing on \(step)")
            XCTAssertEqual(menu.frame.maxX, welcomeFrame.maxX, accuracy: 1, "Menu moved on \(step)")
            XCTAssertEqual(menu.frame.minY, welcomeFrame.minY, accuracy: 1, "Menu moved on \(step)")
        }
    }

    func testOnboardingMenuInEditMode() {
        app.terminate()
        app.launchArguments = ["-ArchySkipOnboarding", "YES", "-accessibility.voiceGuidance", "NO"]
        app.launch()
        tap("home.editAnswers")
        let menu = app.buttons["onboarding.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "Missing menu in edit mode")
        sleep(1)
        capture("edit-goal")
        let goalFrame = menu.frame
        for (id, step) in [("quiz.goal.understandArch", "background"), ("quiz.diagnosis.none", "pain")] {
            tap(id)
            XCTAssertTrue(app.buttons["quiz.back"].waitForExistence(timeout: 5))
            sleep(1)
            XCTAssertTrue(menu.exists && menu.isHittable, "Menu missing on \(step) in edit mode")
            XCTAssertEqual(menu.frame, goalFrame, "Menu moved on \(step) in edit mode")
        }
    }

    func testTipsSheetHasReadAloud() {
        app.terminate()
        app.launchArguments = ["-ArchySkipOnboarding", "YES", "-ArchyTab", "scan", "-ArchyRoute", "scan.tips", "-accessibility.voiceGuidance", "NO"]
        app.launch()
        XCTAssertTrue(app.buttons["scan.tips.read"].waitForExistence(timeout: 10), "Missing read-aloud control in the tips sheet")
    }

    func testCoachSoundOptionsToggleAfterStart() {
        app.terminate()
        // No `-accessibility.*` launch arguments here: they would shadow the stored values the menu writes.
        app.launchArguments = ["-ArchySkipOnboarding", "YES", "-ArchyTab", "train"]
        app.launch()
        tap("studio.shortFoot")
        let sound = app.buttons["coach.sound"]
        XCTAssertEqual(sound.value as? String, "Off")

        // Before Start the options work; that's the baseline for the rest.
        flipSoundOption("Read aloud", expecting: "On")
        flipSoundOption("Read aloud", expecting: "Off")

        // Mid-hold: both can be enabled, and each keeps the menu "On" until both are off.
        tap("coach.start")
        XCTAssertTrue(app.buttons["coach.pause"].waitForExistence(timeout: 5))
        sleep(2)
        flipSoundOption("Read aloud", expecting: "On")
        flipSoundOption("Sound cues", expecting: "On")

        // Paused: both can be turned back off.
        tap("coach.pause")
        XCTAssertTrue(app.buttons["coach.start"].waitForExistence(timeout: 5))
        flipSoundOption("Read aloud", expecting: "On")
        flipSoundOption("Sound cues", expecting: "Off")
    }

    /// Opens the coach's speaker menu, taps one option, then checks the menu's On/Off state.
    private func flipSoundOption(_ option: String, expecting state: String, file: StaticString = #filePath, line: UInt = #line) {
        let sound = app.buttons["coach.sound"]
        sound.tap()
        sleep(2) // long enough for the countdown to tick under an open menu
        let item = app.buttons[option]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Missing \(option)", file: file, line: line)
        XCTAssertTrue(item.isEnabled, "\(option) is disabled", file: file, line: line)
        item.tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", state), object: sound)
        XCTAssertEqual(XCTWaiter().wait(for: [changed], timeout: 3), .completed, "\(option) did not leave the menu \(state)", file: file, line: line)
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

    // MARK: Units, new exercises and scan import

    /// Restarts the app past onboarding with extra launch arguments.
    private func relaunch(_ arguments: [String]) {
        app.terminate()
        app.launchArguments = ["-ArchySkipOnboarding", "YES", "-accessibility.voiceGuidance", "NO"] + arguments
        app.launch()
    }

    func testWizardAndResultsSwitchToInches() {
        relaunch(["-ArchyTab", "home", "-ArchyRoute", "measure.wizard"])
        let field = app.textFields["measure.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        app.buttons["mm"].tap()
        field.tap()
        field.typeText("260")
        app.buttons["in"].tap()
        // 260 mm is 10.24 in, and the field is spoken in inches.
        XCTAssertEqual(field.value as? String, "10.24")
        XCTAssertTrue(field.label.contains("inches"), field.label)
        capture("17-wizard-inches")

        relaunch(["-ArchyTab", "home", "-ArchyRoute", "measure.results.example"])
        let raw = app.buttons["results.raw"]
        XCTAssertTrue(raw.waitForExistence(timeout: 10))
        sleep(1)
        raw.tap()
        XCTAssertTrue(raw.label.contains("Raw measurements, in"), raw.label)
        capture("18-results-inches")
    }

    func testNewExercisesOpenAndStart() {
        relaunch(["-ArchyTab", "train"])
        for (card, shot) in [("studio.toeYoga", "toe-yoga"), ("studio.heelRaise", "heel-raises")] {
            tap(card, shot: "19-train-library-\(shot)")
            tap("coach.start", shot: "20-\(shot)-idle")
            XCTAssertTrue(app.buttons["coach.pause"].waitForExistence(timeout: 5), "\(shot) did not start")
            sleep(5) // past the lead-in, into the first step
            capture("21-\(shot)-running")
            tap("coach.close")
        }
    }

    func testImportedFlatScanShowsFlatArchAndJoinsTheList() throws {
        let fixture = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../Tests/ScanTests/Fixtures/pranav-flat-left.stl").standardized.path
        try XCTSkipUnless(FileManager.default.fileExists(atPath: fixture), "Fixture missing at \(fixture)")
        relaunch(["-ArchyTab", "scan", "-ArchyImportScan", fixture])

        let flat = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Flat arch'")).firstMatch
        XCTAssertTrue(flat.waitForExistence(timeout: 20), "Imported scan didn't show a flat arch")
        sleep(2)
        capture("22-imported-scan")
        XCTAssertTrue(app.buttons["scan.share"].exists)

        // Back to the intro: the import is now a previous scan with its length and arch.
        app.buttons["scan.new"].tap()
        let previous = app.buttons["scan.previous"].firstMatch
        XCTAssertTrue(previous.waitForExistence(timeout: 10))
        XCTAssertTrue(previous.label.contains("Flat arch"), previous.label)
        app.swipeUp()
        XCTAssertTrue(previous.isHittable)
        sleep(1)
        capture("23-scan-intro-previous")
        previous.tap()
        XCTAssertTrue(flat.waitForExistence(timeout: 10), "Reopening a previous scan didn't show its arch")

        // Swipe to delete asks first, then removes just that scan.
        app.buttons["scan.new"].tap()
        XCTAssertTrue(previous.waitForExistence(timeout: 10))
        app.swipeUp()
        let before = app.buttons.matching(identifier: "scan.previous").count
        previous.swipeLeft()
        app.buttons["Delete"].tap()
        let confirm = app.sheets.buttons["Delete"].exists ? app.sheets.buttons["Delete"] : app.buttons["Delete"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        let removed = NSPredicate { [app] _, _ in app.buttons.matching(identifier: "scan.previous").count == before - 1 }
        wait(for: [expectation(for: removed, evaluatedWith: nil)], timeout: 10)
    }
}
