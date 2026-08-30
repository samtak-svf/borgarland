import XCTest

/// The gap #163 created, closed on the same terms as `DetailsKeyboardTest`.
///
/// The onboarding screen has one text field and one button under a block of
/// prose, which is exactly #110's shape — and #110 was a keyboard covering a
/// submit button, found by a person holding a phone after a signed build, an
/// upload, App Store processing and somebody's evening. The screen was pinned
/// with `safeAreaInset` on the strength of the Android measurement rather than
/// after somebody met the bug, so until now nothing checked that the pinning
/// works. A precaution nobody has watched fire is the same thing this project
/// already wrote an incident about.
///
/// It carries MORE prose than the details screen, so it needs this more, not
/// less: the taller the content above the control, the further an unpinned
/// control falls.
///
/// Decision 0014 governs what is asserted — behaviour, never pixels. Nothing
/// here looks at how the screen is laid out; it asks whether a person can
/// reach the two controls the screen consists of.
///
/// The screen is reached through `-uiTestOnboardingScreen`, which `ReportModel`
/// honours only under `#if DEBUG`. That seam CLEARS the stored address as well
/// as setting the screen, because onboarding writes one on the way out and a
/// simulator keeps its container between runs — without the clear, the first
/// run would test the screen and every run after it would test the camera
/// while reporting success.
final class OnboardingKeyboardTest: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launchOnOnboarding() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestOnboardingScreen"]
        app.launch()
        return app
    }

    /// The address field, scrolled until a tap will actually land on it.
    ///
    /// A PRECONDITION, not an assertion — the same shape and the same reason as
    /// the details screen's helper: the pinned footer can cover the field's
    /// centre at rest, where XCUITest taps, and the resulting failure reads as
    /// "Neither element nor any descendant has keyboard focus", which sounds
    /// like a keyboard defect and is a scrolling one.
    ///
    /// Bounded, and it asserts rather than giving up quietly: a run that cannot
    /// reach the field proves nothing and has to say so.
    private func focusedEmailField(in app: XCUIApplication) -> XCUIElement {
        let field = app.descendants(matching: .any)
            .matching(identifier: "onboarding-email-field").firstMatch
        XCTAssertTrue(
            field.waitForExistence(timeout: 60),
            "the onboarding screen never appeared; the -uiTestOnboardingScreen seam is the suspect"
        )
        var swipes = 0
        while !field.isHittable && swipes < 4 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(
            field.isHittable,
            "the address field never became tappable after \(swipes) swipes, so this run cannot say anything about #110"
        )
        field.tap()
        return field
    }

    private func continueButton(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "onboarding-continue-button").firstMatch
    }

    func testTheContinueButtonStaysHittableWithTheKeyboardUp() {
        let app = launchOnOnboarding()

        let field = focusedEmailField(in: app)
        field.typeText("uitest@example.is")

        // A hard requirement, not a guard. Without the software keyboard —
        // a hardware keyboard attached to the simulator is the usual cause —
        // this run proves nothing about #110, and a test that can quietly
        // prove nothing is worse than no test.
        XCTAssertTrue(
            app.keyboards.element.waitForExistence(timeout: 15),
            "the software keyboard did not appear, so this run cannot say anything about #110"
        )

        let button = continueButton(in: app)
        XCTAssertTrue(button.waitForExistence(timeout: 5), "the continue button is not on the screen")

        // Not the assertion, but it has to hold for the next one to mean
        // anything: a control disabled for an unrelated reason could report
        // whatever it liked about hittability. Here it doubles as the check
        // that a valid address enables the button, which is this screen's
        // whole rule.
        XCTAssertTrue(
            button.isEnabled,
            "a valid address did not enable the continue button, so this run cannot say anything about #110"
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
        let app = launchOnOnboarding()

        let field = focusedEmailField(in: app)
        field.typeText("uitest@example.is")
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 15))

        // #79: two ways down, because one of them is a gesture nobody is told
        // about. This screen is where somebody meets the app for the first
        // time, so the visible way matters more here than anywhere.
        let close = app.buttons["Loka lyklaborði"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "no visible way to put the keyboard away (#79)")
        close.tap()

        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.keyboards.element)
        waitForExpectations(timeout: 10)
    }

    /// The screen's own rule, which the keyboard tests only touch in passing.
    ///
    /// The address is required BY US and optional to the city (decision 0015),
    /// and this screen is the one place a person can be stopped by that. The
    /// refusal lives in the contract's `valueFor` loop rather than in the
    /// interface — so what is asserted here is that the interface AGREES with
    /// it, not that it enforces it.
    func testTheScreenRefusesToBeLeftWithoutAnAddress() {
        let app = launchOnOnboarding()

        let button = continueButton(in: app)
        XCTAssertTrue(button.waitForExistence(timeout: 60), "the onboarding screen never appeared")

        // An untouched field on a first launch: nothing typed, nowhere to go.
        XCTAssertFalse(button.isEnabled, "onboarding could be left without an address (#163)")

        let field = focusedEmailField(in: app)

        // A typo of exactly the kind ContactDetails.isValid exists to catch —
        // it looks like an address and loses the confirmation silently.
        field.typeText("nafn@")
        XCTAssertFalse(button.isEnabled, "a domain-less address enabled the continue button")

        field.typeText("daemi.is")
        // Waiting rather than asserting immediately: the enablement travels
        // through the model and the value is read after the last keystroke,
        // not with it.
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: button)
        waitForExpectations(timeout: 10)
    }
}
