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
