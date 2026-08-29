import XCTest

/// The test #110 did not have.
///
/// A keyboard covering a submit button compiles perfectly, passes every unit
/// test, and is plainly visible in any screenshot. It was found by a person
/// holding a phone, and the loop that found it was a signed build, an upload,
/// App Store processing and somebody's evening.
///
/// This is the cheap half of that loop. It cannot replace a phone in a hand —
/// `data/field-tests.json` exists because the two find different things — but
/// a layout regression of exactly this shape should not cost a tester's night
/// again.
///
/// The app opens on the camera and a simulator has no camera, so the details
/// screen is reached through the `-uiTestDetailsScreen` launch argument, which
/// `ReportModel` honours only under `#if DEBUG`.
final class DetailsKeyboardTest: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launchOnDetails() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestDetailsScreen"]
        app.launch()
        return app
    }

    func testTheContinueButtonStaysHittableWithTheKeyboardUp() {
        let app = launchOnDetails()

        let field = app.descendants(matching: .any)
            .matching(identifier: "description-field").firstMatch
        XCTAssertTrue(
            field.waitForExistence(timeout: 60),
            "the details screen never appeared; the -uiTestDetailsScreen seam is the suspect"
        )

        field.tap()
        field.typeText("Prufa")

        // A hard requirement, not a guard. If the software keyboard never
        // comes up — a hardware keyboard attached to the simulator is the
        // usual cause — then this test proves nothing about #110, and a test
        // that can quietly prove nothing is worse than no test.
        XCTAssertTrue(
            app.keyboards.element.waitForExistence(timeout: 15),
            "the software keyboard did not appear, so this run cannot say anything about #110"
        )

        let button = app.descendants(matching: .any)
            .matching(identifier: "continue-button").firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "the continue button is not on the screen")

        // Neither is `isEnabled`, but it has to hold for the next assertion to
        // mean anything: a control disabled for an unrelated reason could
        // report whatever it liked about hittability and the test would still
        // pass. The address the screen now requires (#163) is seeded by the
        // -uiTestDetailsScreen seam for exactly this reason.
        XCTAssertTrue(
            button.isEnabled,
            "the continue button is disabled, so this run cannot say anything about #110"
        )

        // `exists` is not the assertion. #110's button existed the whole time;
        // it was underneath the keyboard, which is what isHittable answers and
        // nothing else in this repository does.
        XCTAssertTrue(
            button.isHittable,
            "#110: the continue button is on screen but not hittable with the keyboard up"
        )
    }

    func testTheKeyboardCanBeDismissedByAControlAndNotOnlyByAGesture() {
        let app = launchOnDetails()

        let field = app.descendants(matching: .any)
            .matching(identifier: "description-field").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 60))
        field.tap()
        field.typeText("Prufa")
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 15))

        // #79: two ways down, because one is a gesture nobody is told about.
        // The toolbar button is the one somebody can see.
        let close = app.buttons["Loka lyklaborði"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "no visible way to put the keyboard away (#79)")
        close.tap()

        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.keyboards.element)
        waitForExpectations(timeout: 10)
    }
}
