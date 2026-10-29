import AskUI
import FoundationModels
import UIKit
import XCTest

/// The Ask screen, driven the way a reader drives it.
///
/// **Mechanics, never prose.** A model writes a different sentence every time,
/// so an assertion about what an answer *says* measures the seed. These assert
/// what has to be true whatever it says: a chip starts a turn, the send button
/// becomes a stop, a stopped turn keeps its question and offers Try Again, New
/// Chat empties the thread, the tier caption names who answered.
///
/// It is also the only thing in this repo that runs the screen, and some
/// defects live only there, past every unit test and every build: an
/// identifier swallowed by the screen's own root identifier, or a keyboard with
/// no way out. So `ask.send` is asserted by identifier, and each way out of
/// the keyboard a reader takes has a test: the send, a tap on the screen, the
/// composer's chevron and Done.
///
/// **Where a test's assumption fails, it skips and says which.** The suite
/// runs on an iPhone, an iPad and iPhone Duo, and some tests assume a phone: a
/// bottom tab bar whose slot holds the composer's face, `XCUIDevice` turning
/// the device, the bars along the top and the foot. One guard for each
/// (`requireTheFaceInTheSlot()`, `requireXCUIDeviceToTurnTheDevice()` and
/// `turn(_:onItsSide:)`, `requireBarsAlongTheTopAndFoot(_:_:)`) skips with
/// the reason, and none of them skips anything on an iPhone.
///
/// **The isolation is split on purpose.** The class is `nonisolated` because
/// `XCTestCase`'s initialisers and `setUp()` are, and the target is
/// MainActor-by-default like the rest of the project — a MainActor class cannot
/// override them. Every *test* is `@MainActor` because `XCUIApplication` and
/// every query on it is: a nonisolated test body compiles and emits an
/// `[#ActorIsolatedCall]` warning per call, and the push gate fails on those.
nonisolated final class AskScreenSmokeTests: XCTestCase {

    // MARK: Identifiers — the namespace every host's UI tests share

    /// `AskAccessibility` itself, not a second copy of its values.
    ///
    /// A twice-typed literal fails silently, the reason
    /// `Demo/Shared/DemoLaunchArgument.swift` exists: with copies here, a
    /// renamed identifier would leave this suite green against strings nothing
    /// sets any more.
    private typealias Ids = AskAccessibility

    /// Long enough for a cold on-device turn — the first of a launch loads the
    /// model — and short enough that a hang is a failure rather than a
    /// forty-minute wait.
    private let turnTimeout: TimeInterval = 90
    private let uiTimeout: TimeInterval = 10

    /// Skip rather than fail where there is no model: this suite runs on
    /// whatever simulator is to hand, and a device without Apple Intelligence
    /// has nothing wrong with it.
    @MainActor
    private func launch(_ arguments: String...) throws -> XCUIApplication {
        guard case .available = SystemLanguageModel.default.availability else {
            throw XCTSkip("No on-device model on this simulator — nothing to drive.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        // The thread is persisted, so without this the first assertion of the
        // run depends on what the test before it left on disk.
        app.launchArguments = [DemoLaunchArgument.resetThread] + arguments
        app.launch()
        // **Queried across every element type, not as an `otherElements`.**
        // Which XCUI type `ask.root` lands on is decided by what the thread's
        // container collapses to, and that changes with the layout: it is a
        // scroll view on the first screen and on a thread, and a layout change
        // that breaks nothing can make it another type, failing every query by
        // type at once. An identifier that means "the screen is up" should be
        // asked for by identifier alone.
        XCTAssertTrue(root(app).waitForExistence(timeout: uiTimeout))
        return app
    }

    /// Launch with a scripted answer (`DemoLaunchArgument.scriptedAnswer`):
    /// tiles, no follow-ups, no model.
    ///
    /// No `XCTSkip`: these tests are about *mechanics*, such as a tile opening
    /// the row it names, and made conditional on the model's choices they
    /// would report green having checked nothing whenever it chose otherwise.
    /// With no model needed, they run without Apple Intelligence too.
    @MainActor
    private func launchScripted(_ arguments: String...) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [DemoLaunchArgument.resetThread, DemoLaunchArgument.scriptedAnswer] + arguments
        app.launch()
        XCTAssertTrue(root(app).waitForExistence(timeout: uiTimeout))
        return app
    }

    @MainActor
    private func root(_ app: XCUIApplication) -> XCUIElement {
        element(Ids.root, in: app)
    }

    /// By identifier alone, across every element type.
    ///
    /// The reason `launch(_:)` gives for `ask.root`, and it is not special to
    /// the root: which XCUI type an identifier lands on depends on what the
    /// view collapses to, and that moves with the accessibility modifiers on
    /// it. `ask.answer` is one element with its own label and value rather
    /// than a `staticText`, for VoiceOver's sake, and a change like that
    /// breaks a query by type silently, because the push gate builds this
    /// bundle and does not run it.
    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Wait for an element's label to become `label`.
    ///
    /// The stop turning back into the arrow is a *transition*, not a state
    /// that is true the instant the answer lands: the answer arrives as an
    /// event and the turn settles when the stream after it finishes. Asserted
    /// without waiting, it can fail, correctly.
    ///
    /// **The arrow has two names.** With a draft to send it is Send; with the
    /// field empty, which is how every turn leaves it, a tap only takes the
    /// reader to the field, and it is Write a question.
    @MainActor
    private func wait(_ element: XCUIElement, label: String) {
        let matched = expectation(
            for: NSPredicate(format: "label == %@", label), evaluatedWith: element
        )
        wait(for: [matched], timeout: uiTimeout)
    }

    // MARK: What a test assumes of the device

    /// Whether the runner is on an iPad, whose tab bar hangs off the top at
    /// regular width.
    @MainActor
    private var runsOnAnIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    /// Whether the runner is on iPhone Duo's simulator, by the model
    /// identifier the simulator hands every process: `iPhone19,4` on the Duo's
    /// iOS 27.2 runtime, where the iPhone 18 Pro is `iPhone19,2`.
    private var runsOnIPhoneDuo: Bool {
        ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,4"
    }

    /// Skip a test of the composer's face in the tab bar's slot where the slot
    /// holds none: an iPad at regular width hangs its tab bar off the top, and
    /// there the composer stays in the screen's own bar by design
    /// (`AskComposerSlotPolicy.tabBarRunsAlongBottom`). iPhone Duo's strip
    /// reports a bottom bar, and its slot holds the face.
    @MainActor
    private func requireTheFaceInTheSlot() throws {
        if runsOnAnIPad {
            throw XCTSkip(
                "Needs a phone's bottom tab bar: an iPad's hangs off the top at regular width, "
                + "and by design its slot holds no face."
            )
        }
    }

    /// Why a test that turns the device skips where nothing turns it.
    private static let cannotTurn = "Needs XCUIDevice to turn the device: on iPhone Duo it changes only "
        + "the orientation the device reports, and both displays stay as they were."

    /// Skip a test that turns the device both ways where `XCUIDevice` can't:
    /// on iPhone Duo Device Hub's Rotate does it, from outside the test.
    private func requireXCUIDeviceToTurnTheDevice() throws {
        if runsOnIPhoneDuo { throw XCTSkip(Self.cannotTurn) }
    }

    /// Turn the device onto its side or upright, and wait for the window to
    /// follow. Onto its side, a teardown turns it upright again even when an
    /// assertion stops the test: whatever runs next on this simulator expects
    /// a phone upright.
    ///
    /// **iPhone Duo is taken as it is**, since nothing in a test turns it: the
    /// test goes on where the window is that way already, and skips where it
    /// isn't. It is never turned and then skipped for not turning, which would
    /// hide a phone's failed turn.
    @MainActor
    private func turn(_ app: XCUIApplication, onItsSide: Bool) throws {
        if runsOnIPhoneDuo {
            let window = app.windows.firstMatch.frame
            guard (window.width > window.height) == onItsSide else { throw XCTSkip(Self.cannotTurn) }
            return
        }
        if onItsSide {
            addTeardownBlock { @MainActor in XCUIDevice.shared.orientation = .portrait }
        }
        XCUIDevice.shared.orientation = onItsSide ? .landscapeLeft : .portrait
        waitForTurn(of: app, onItsSide: onItsSide)
    }

    /// Skip where the bars are in iPhone Duo's strip at the side rather than
    /// along the top and the foot, `consequence` saying what the strip does
    /// that the test can't allow for.
    ///
    /// Read from the tree, so a pose with its bars along the top runs: in the
    /// strip New Chat is in the strip's toolbar, under no navigation bar. On
    /// the Duo alone, so whatever a phone's tree comes to, a phone never skips.
    @MainActor
    private func requireBarsAlongTheTopAndFoot(_ app: XCUIApplication, _ consequence: String) throws {
        guard runsOnIPhoneDuo else { return }
        XCTAssertTrue(app.buttons[Ids.clear].waitForExistence(timeout: uiTimeout))
        if !app.navigationBars.buttons[Ids.clear].exists {
            throw XCTSkip("Needs a phone's bars along the top and the foot, not iPhone Duo's strip: \(consequence)")
        }
    }

    /// One of the demo's tabs, by its label (`Text(verbatim:)` in the demo).
    ///
    /// Not through the tab bar: an iPad's along the top is no `TabBar`
    /// element, and in iPhone Duo's strip the tab buttons aren't the
    /// `TabBar`'s descendants. The first match, because the iPad lists each
    /// tab's button twice, one inside the other. A minimized tab bar lists the
    /// selected tab alone, so a query for the other one finds nothing, by
    /// label as through the bar.
    @MainActor
    private func tab(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    // MARK: The first screen

    @MainActor
    func testTheFirstScreenOffersThreeStarters() throws {
        let app = try launch()
        let starters = element(Ids.starters, in: app)
        XCTAssertTrue(starters.waitForExistence(timeout: uiTimeout))
        XCTAssertEqual(starters.buttons.count, 3, "The first screen offers exactly three starters.")
    }

    /// The subtitle is applied even before a tier resolves, so the bar never
    /// changes height mid-turn. With no Private Cloud Compute entitlement, the
    /// demo can only ever answer on the device.
    ///
    /// Matched with `CONTAINS` rather than on the exact string. The caption is
    /// the tier's name alone (`AskTierCaption` says why), but a subtitle is one
    /// node among several the bar composes, so containment is what survives
    /// the bar rearranging itself. "Private Cloud Compute" and "On device" are
    /// the two values, and the first is `shouldTranslate: false`.
    @MainActor
    func testTheTierCaptionNamesTheOnDeviceModel() throws {
        let app = try launch()
        let caption = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "On device")
        ).firstMatch
        XCTAssertTrue(
            caption.waitForExistence(timeout: uiTimeout),
            "The demo has no Private Cloud Compute entitlement."
        )
    }

    /// A host usually puts Ask in a tab. On an iPad at regular width the tab
    /// bar takes the middle of the navigation bar, where the title and its
    /// subtitle would be, and neither is drawn, so the caption leads the bar
    /// there (`AskTierCaption`). On an iPhone the tab bar is at the bottom and
    /// the caption is the subtitle. Either way it's on screen, and it stays
    /// there with Done in the bar while the composer has focus.
    ///
    /// `scripts/ui-smoke.sh` runs it on an iPhone. The iPad half needs an iPad
    /// such as the iPad mini (A17 Pro), by UDID: full screen, it is regular
    /// width either way up.
    @MainActor
    func testTheTierCaptionIsInViewWhenAskIsATab() throws {
        let app = try launch(DemoLaunchArgument.tabs)
        let caption = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "On device")
        ).firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(caption.isHittable, "The caption is on screen, not only in the tree.")

        let field = app.textFields[Ids.field]
        XCTAssertTrue(field.waitForExistence(timeout: uiTimeout))
        field.tap()
        XCTAssertTrue(app.buttons[Ids.done].waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(caption.isHittable, "Done joins the bar and leaves the caption in view.")
    }

    // MARK: A turn

    @MainActor
    func testAStarterStartsATurnAndTheButtonBecomesAStop() throws {
        let app = try launch()
        let starters = element(Ids.starters, in: app)
        XCTAssertTrue(starters.waitForExistence(timeout: uiTimeout))
        starters.buttons.element(boundBy: 0).tap()

        // The wait row, and the question that caused it.
        XCTAssertTrue(element(Ids.thinking, in: app).waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(element(Ids.question, in: app).exists)

        // Same spot, same circle, the other verb. `ask.send` is asserted by
        // identifier on purpose: the screen's root identifier can swallow it,
        // and a query by label alone would not notice.
        let button = app.buttons[Ids.send]
        XCTAssertTrue(button.exists)
        XCTAssertEqual(button.label, "Cancel")

        // And the turn lands: prose, and the button back to the arrow, over an
        // empty field it takes the reader to.
        XCTAssertTrue(element(Ids.answer, in: app).waitForExistence(timeout: turnTimeout))
        wait(button, label: "Write a question")
    }

    @MainActor
    func testTypingAndSendingStartsATurn() throws {
        let app = try launch()
        let field = app.textFields[Ids.field]
        XCTAssertTrue(field.waitForExistence(timeout: uiTimeout))
        field.tap()
        field.typeText("How many things do I own in total?")

        // The arrow, not the keyboard's return key. On a vertical-axis field
        // the software return never fires `onSubmit`, so the composer
        // deliberately does not claim it — a hardware return sends, and the
        // arrow is what a phone has.
        app.buttons[Ids.send].tap()
        XCTAssertTrue(element(Ids.question, in: app).waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(element(Ids.answer, in: app).waitForExistence(timeout: turnTimeout))
    }

    /// Nothing the thread has shown is taken back: a stopped turn keeps its
    /// question, and there is a way onward from it.
    @MainActor
    func testStoppingKeepsTheQuestionAndOffersTryAgain() throws {
        let app = try launch()
        let starters = element(Ids.starters, in: app)
        XCTAssertTrue(starters.waitForExistence(timeout: uiTimeout))
        starters.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element(Ids.thinking, in: app).waitForExistence(timeout: uiTimeout))

        app.buttons[Ids.send].tap()   // reads "Cancel" here
        XCTAssertTrue(element(Ids.question, in: app).exists, "The question stays on the thread.")
        // Either the turn had written nothing and offers Try Again, or it had
        // and keeps its text as the answer. Both are terminal states with
        // something on the thread; neither is an empty thread.
        let tryAgain = app.buttons[Ids.retry]
        let answer = element(Ids.answer, in: app)
        XCTAssertTrue(
            tryAgain.waitForExistence(timeout: uiTimeout) || answer.exists,
            "A stopped turn either offers Try Again or keeps what it had written."
        )
    }

    /// Type and send questions until the thread overflows the window, which
    /// is the first question gone up out of it: three at least, which is what
    /// a phone takes, and four in an iPad mini's taller window.
    @MainActor
    private func askUntilTheThreadOverflows(_ app: XCUIApplication) {
        let field = app.textFields[Ids.field]
        XCTAssertTrue(field.waitForExistence(timeout: uiTimeout))
        let send = app.buttons[Ids.send]
        let answers = app.descendants(matching: .any).matching(identifier: Ids.answer)
        let questions = app.descendants(matching: .any).matching(identifier: Ids.question)
        for index in 1...8 {
            field.tap()
            field.typeText("Question \(index) about my things")
            send.tap()
            XCTAssertTrue(answers.element(boundBy: index - 1).waitForExistence(timeout: turnTimeout))
            wait(send, label: "Write a question")
            if index >= 3, questions.firstMatch.frame.maxY <= app.windows.firstMatch.frame.minY { return }
        }
        XCTFail("Eight turns and the thread still fits the window.")
    }

    /// A reader at the foot of a thread is still there with the phone on its
    /// side, and upright again.
    ///
    /// The failure it guards: unless `AskScrollFollow` knows a resize, a frame
    /// after the new width the scroll view steps 117pt up the thread, the step
    /// reads as the reader's, and the newest answer comes out of the turn below
    /// the window with "Jump to latest" offering the way back.
    @MainActor
    func testAThreadAtItsFootStaysThereOnItsSide() throws {
        try requireXCUIDeviceToTurnTheDevice()
        let app = launchScripted()
        let field = app.textFields[Ids.field]
        XCTAssertTrue(field.waitForExistence(timeout: uiTimeout))
        let send = app.buttons[Ids.send]
        let answers = app.descendants(matching: .any).matching(identifier: Ids.answer)
        // Three turns, so the thread overflows upright as well as on its side.
        for index in 1...3 {
            field.tap()
            field.typeText("Question \(index) about my things")
            send.tap()
            XCTAssertTrue(answers.element(boundBy: index - 1).waitForExistence(timeout: turnTimeout))
            wait(send, label: "Write a question")
        }
        let pill = element(Ids.jumpToLatest, in: app)
        _ = settledNewestAnswer(in: app)

        // Upright again even when an assertion below stops the test, for the
        // reason `testTheFirstScreenFitsAPhoneOnItsSide` gives.
        addTeardownBlock { @MainActor in XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForTurn(of: app, onItsSide: true)
        XCTAssertLessThanOrEqual(
            settledNewestAnswer(in: app).maxY, send.frame.minY, "On its side, the newest answer is in view."
        )
        XCTAssertFalse(pill.exists, "Nothing offers the way back to where the reader already is.")

        XCUIDevice.shared.orientation = .portrait
        waitForTurn(of: app, onItsSide: false)
        XCTAssertLessThanOrEqual(settledNewestAnswer(in: app).maxY, send.frame.minY, "Upright again, it still is.")
        XCTAssertFalse(pill.exists, "Upright again, nothing offers the way back.")
    }

    /// The navigation bar minimizes for the reader and never for the follow,
    /// the keyboard opens it so Done can be reached, and Done leaves it open.
    /// The host's tab bar minimizes with it, for the reader alone too.
    ///
    /// In tabs, as a host usually has Ask. The bars are read by their items:
    /// XCUI reports a minimized bar at its expanded frame, but a minimized
    /// navigation bar lists no buttons, and a minimized tab bar lists one, the
    /// tab the reader is on. An iPad's tab bar, along the top, lists none.
    @MainActor
    func testTheNavigationBarMinimizesForTheReaderAndOpensForTheKeyboard() throws {
        let app = launchScripted(DemoLaunchArgument.tabs)
        try requireBarsAlongTheTopAndFoot(
            app, "the strip keeps New Chat and both tabs as the reader scrolls down, so nothing minimizes."
        )
        // So the thread has somewhere to scroll.
        askUntilTheThreadOverflows(app)
        let field = app.textFields[Ids.field]
        let newChat = app.navigationBars.buttons[Ids.clear]
        XCTAssertTrue(newChat.isHittable, "Following the answers to the foot minimizes nothing.")
        // The demo's second tab, which a minimized tab bar leaves out.
        let library = tab("Library", in: app)
        XCTAssertTrue(library.exists, "Not the tab bar either.")

        // Up the thread and back down it, so the scroll down is the reader's.
        root(app).swipeDown()
        root(app).swipeUp()
        XCTAssertTrue(newChat.waitForNonExistence(timeout: uiTimeout), "The reader's scroll down minimizes the bar.")
        XCTAssertTrue(library.waitForNonExistence(timeout: uiTimeout), "It minimizes the tab bar too.")

        field.tap()
        let done = app.buttons[Ids.done]
        XCTAssertTrue(done.waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(done.isHittable, "The keyboard opens the navigation bar, so Done is there to put it away.")
        done.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: uiTimeout))
        XCTAssertTrue(newChat.waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(newChat.isHittable, "Done leaves the bar open.")
    }

    /// Where the newest answer in the tree comes to rest, once two readings a
    /// beat apart agree.
    ///
    /// The last `ask.answer` rather than one at an index, because the thread
    /// is lazy: on its side it keeps two answers of five, so an index taken
    /// upright names nothing once the phone has turned.
    @MainActor
    private func settledNewestAnswer(in app: XCUIApplication) -> CGRect {
        let answers = app.descendants(matching: .any).matching(identifier: Ids.answer)
        var last = answers.allElementsBoundByIndex.last?.frame ?? .null
        for _ in 0..<30 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            let now = answers.allElementsBoundByIndex.last?.frame ?? .null
            if abs(now.minY - last.minY) < 0.5 { return now }
            last = now
        }
        return last
    }

    // MARK: The composer in a tab bar's slot

    /// The slot holds the composer's face, and a tap on it raises the screen's
    /// own composer over the keyboard: a field in the slot stays under the
    /// keyboard, so the face never takes the typing. The keyboard going takes
    /// the composer back down and leaves the draft on the face, which sends it.
    ///
    /// **Read by hittability, never by existence.** XCUI lists an element
    /// SwiftUI hides from accessibility all the same — the resting composer
    /// and the face under the keyboard both stay in its tree — while
    /// VoiceOver reaches only the one in sight. Walked from inside the demo
    /// the way VoiceOver walks it: at rest the face alone, the composer alone
    /// while it is up, and the face alone again after Done.
    @MainActor
    func testTheSlotRaisesTheComposerOverTheKeyboardAndTakesItBack() throws {
        try requireTheFaceInTheSlot()
        let app = launchScripted(DemoLaunchArgument.tabs, DemoLaunchArgument.slot)
        let face = element(Ids.slotField, in: app)
        XCTAssertTrue(face.waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(face.isHittable)
        let field = app.textFields[Ids.field]
        XCTAssertFalse(field.isHittable, "At rest the screen's own composer is out of reach.")

        face.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: uiTimeout))
        wait(field, hittable: true, "The tap raises the screen's composer.")
        XCTAssertLessThanOrEqual(field.frame.maxY, keyboard.frame.minY, "It sits over the keyboard.")
        wait(face, hittable: false, "The face waits under the keyboard.")

        let question = "What is the oldest thing I have"
        field.typeText(question)
        app.buttons[Ids.done].tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: uiTimeout))
        wait(field, hittable: false, "The composer goes back down with the keyboard.")
        wait(face, hittable: true, "The face is back in reach.")
        XCTAssertEqual(face.value as? String, question, "The face carries the draft.")

        element(Ids.slotSend, in: app).tap()
        XCTAssertTrue(element(Ids.answer, in: app).waitForExistence(timeout: turnTimeout), "The face's send asks it.")
    }

    /// The composer's placeholder is drawn and never read: with an empty draft
    /// there is one thing called "Your question", the field.
    ///
    /// **By existence, for once.** XCUI lists what SwiftUI hides from
    /// accessibility (the test above has that), so hiding the placeholder
    /// wouldn't pass this: it has no element at all (`AskComposer.field` says
    /// why hiding it wasn't enough).
    @MainActor
    func testTheComposersPlaceholderIsNoElementOfItsOwn() {
        let app = launchScripted()
        XCTAssertTrue(app.textFields[Ids.field].waitForExistence(timeout: uiTimeout))
        let called = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Your question"))
        let found = called.allElementsBoundByIndex.map { "\($0.elementType.rawValue) \($0.frame)" }
        XCTAssertEqual(found.count, 1, "Only the field answers to the field's name: \(found)")
    }

    /// The face rides with the tab bar as it minimizes: above the expanded bar,
    /// beside the Ask button on its row once the reader's scroll minimizes the
    /// bar, and back above the bar when it expands.
    @MainActor
    func testTheSlotRidesBesideTheMinimizedTabBar() throws {
        try requireTheFaceInTheSlot()
        let app = launchScripted(DemoLaunchArgument.tabs, DemoLaunchArgument.slot)
        try requireBarsAlongTheTopAndFoot(
            app, "the tab bar stays whole in the strip as the reader scrolls down, so there is no row to ride beside."
        )
        let face = element(Ids.slotField, in: app)
        XCTAssertTrue(face.waitForExistence(timeout: uiTimeout))
        let field = app.textFields[Ids.field]
        let answers = app.descendants(matching: .any).matching(identifier: Ids.answer)
        // Three turns, typed the way a reader types here, so the thread has
        // somewhere to scroll.
        for index in 1...3 {
            face.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: uiTimeout))
            field.typeText("Question \(index) about my things")
            app.buttons[Ids.send].tap()
            XCTAssertTrue(answers.element(boundBy: index - 1).waitForExistence(timeout: turnTimeout))
            wait(element(Ids.slotSend, in: app), label: "Write a question")
        }
        let ask = tab("Ask", in: app)
        let library = tab("Library", in: app)
        XCTAssertTrue(library.exists, "The bar is expanded.")
        XCTAssertLessThanOrEqual(settledFrame(of: face).maxY, ask.frame.minY, "Expanded, the face sits above the bar.")

        // Up the thread and back down it, so the scroll down is the reader's.
        root(app).swipeDown()
        root(app).swipeUp()
        XCTAssertTrue(library.waitForNonExistence(timeout: uiTimeout), "The reader's scroll down minimizes the bar.")
        let button = settledFrame(of: ask)
        let minimized = settledFrame(of: face)
        XCTAssertGreaterThan(minimized.minX, button.maxX, "With the bar minimized, the face is beside the Ask button,")
        XCTAssertEqual(minimized.midY, button.midY, accuracy: 4, "on its row.")

        root(app).swipeDown()
        XCTAssertTrue(library.waitForExistence(timeout: uiTimeout), "The reader's scroll up expands the bar.")
        XCTAssertLessThanOrEqual(settledFrame(of: face).maxY, ask.frame.minY, "The face goes back above it.")
    }

    /// The slot is the Ask tab's: another tab has no composer in it but the
    /// host's own accessory, and coming back brings the face back in its place.
    @MainActor
    func testTheSlotIsTheAskTabsAlone() throws {
        try requireTheFaceInTheSlot()
        let app = launchScripted(DemoLaunchArgument.tabs, DemoLaunchArgument.slot)
        let face = element(Ids.slotField, in: app)
        let glance = element(DemoAccessibility.glance, in: app)
        XCTAssertTrue(face.waitForExistence(timeout: uiTimeout))
        XCTAssertFalse(glance.exists, "On Ask the slot is the composer's.")
        tab("Library", in: app).tap()
        XCTAssertTrue(face.waitForNonExistence(timeout: uiTimeout), "Another tab has no composer in the slot,")
        XCTAssertTrue(glance.waitForExistence(timeout: uiTimeout), "and the host's own accessory has it.")
        tab("Ask", in: app).tap()
        XCTAssertTrue(face.waitForExistence(timeout: uiTimeout), "Back on Ask, the face is back,")
        XCTAssertTrue(face.isHittable)
        XCTAssertTrue(glance.waitForNonExistence(timeout: uiTimeout), "in the accessory's place.")
    }

    /// The keyboard put away stays away across a trip to another tab: back on
    /// Ask, the reader finds the face, not a keyboard over the tab bar.
    /// Through Done here; the send, the chevron, a tap on the screen and a
    /// drag all brought it back the same way.
    ///
    /// **Asserted as never coming back, not as gone.** The keyboard is already
    /// gone the instant Ask returns; it came back as the tab settled, so the
    /// test gives it the time it took.
    @MainActor
    func testTheKeyboardPutAwayStaysAwayAcrossATabSwitch() throws {
        try requireTheFaceInTheSlot()
        let app = launchScripted(DemoLaunchArgument.tabs, DemoLaunchArgument.slot)
        let face = element(Ids.slotField, in: app)
        XCTAssertTrue(face.waitForExistence(timeout: uiTimeout))
        face.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: uiTimeout))
        let done = app.buttons[Ids.done]
        XCTAssertTrue(done.waitForExistence(timeout: uiTimeout))
        done.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: uiTimeout))

        tab("Library", in: app).tap()
        XCTAssertTrue(face.waitForNonExistence(timeout: uiTimeout))
        tab("Ask", in: app).tap()
        XCTAssertTrue(face.waitForExistence(timeout: uiTimeout))
        XCTAssertFalse(keyboard.waitForExistence(timeout: 3), "Back on Ask, the keyboard stays away,")
        wait(face, hittable: true, "and the face is in reach.")
    }

    /// An item pushed over the thread hides the screen, and the face goes
    /// with it: the item has no composer for the face to raise. A trip to
    /// another tab and back finds the item still on top and the face still
    /// away, and going back to the thread brings the face back. The screen
    /// tells the slot all of this; the demo, like any host, only pushes.
    @MainActor
    func testAnItemPushedOverTheThreadTakesTheFaceWithIt() throws {
        try requireTheFaceInTheSlot()
        let app = launchScripted(DemoLaunchArgument.tabs, DemoLaunchArgument.slot, DemoLaunchArgument.push)
        let face = element(Ids.slotField, in: app)
        let glance = element(DemoAccessibility.glance, in: app)
        XCTAssertTrue(face.waitForExistence(timeout: uiTimeout))
        let starters = element(Ids.starters, in: app)
        XCTAssertTrue(starters.waitForExistence(timeout: uiTimeout))
        starters.buttons.element(boundBy: 0).tap()
        let tiles = element(Ids.results, in: app)
        XCTAssertTrue(tiles.waitForExistence(timeout: turnTimeout), "The scripted answer shows tiles.")
        tiles.buttons.element(boundBy: 0).tap()

        let detailTitle = app.staticTexts[DemoAccessibility.rowDetailTitle]
        XCTAssertTrue(detailTitle.waitForExistence(timeout: uiTimeout), "The tile pushes its row,")
        XCTAssertTrue(face.waitForNonExistence(timeout: uiTimeout), "and the face goes with the thread.")

        tab("Library", in: app).tap()
        XCTAssertTrue(glance.waitForExistence(timeout: uiTimeout))
        tab("Ask", in: app).tap()
        XCTAssertTrue(glance.waitForNonExistence(timeout: uiTimeout))
        XCTAssertTrue(detailTitle.exists, "Back on Ask the row is still on top,")
        XCTAssertFalse(face.exists, "and the face is still away.")

        // The system's back button, by the identifier UIKit gives it: in
        // iPhone Duo's strip it is under no navigation bar.
        app.buttons["BackButton"].tap()
        XCTAssertTrue(detailTitle.waitForNonExistence(timeout: uiTimeout))
        XCTAssertTrue(face.waitForExistence(timeout: uiTimeout), "The thread coming back brings the face.")
        wait(face, hittable: true, "The face is in reach.")
    }

    /// The face carries the screen's accessory button, here the photo button,
    /// with no hand from the host: the photo it attaches waits over the face,
    /// then over the composer the face raises, and goes with the question.
    @MainActor
    func testTheFacesPhotoButtonAttachesAPhotoThatGoesWithTheQuestion() throws {
        try requireTheFaceInTheSlot()
        let app = launchScripted(DemoLaunchArgument.tabs, DemoLaunchArgument.slot, DemoLaunchArgument.photos)
        let face = element(Ids.slotField, in: app)
        XCTAssertTrue(face.waitForExistence(timeout: uiTimeout))
        // Two photo buttons: the face's, and the resting composer's, out of reach.
        let attach = app.buttons.matching(identifier: Ids.attach).allElementsBoundByIndex.first { $0.isHittable }
        guard let attach else { return XCTFail("The face offers the photo button.") }
        attach.tap()

        let pending = element(Ids.pendingPhoto, in: app)
        XCTAssertTrue(pending.waitForExistence(timeout: uiTimeout), "The photo waits,")
        XCTAssertTrue(pending.isHittable)
        XCTAssertLessThanOrEqual(settledFrame(of: pending).maxY, settledFrame(of: face).minY, "over the face.")

        face.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: uiTimeout))
        let field = app.textFields[Ids.field]
        wait(field, hittable: true, "The tap raises the composer,")
        XCTAssertLessThanOrEqual(settledFrame(of: pending).maxY, field.frame.minY, "and the photo waits over it.")
        field.typeText("What goes with this?")
        app.buttons[Ids.send].tap()
        XCTAssertTrue(element(Ids.answer, in: app).waitForExistence(timeout: turnTimeout))
        XCTAssertTrue(element(Ids.questionPhoto, in: app).exists, "The photo went with the question.")
    }

    /// Wait for an element to come into reach, or go out of it. The composer
    /// and its face trade places on the keyboard's clock, so a reading taken
    /// the instant the keyboard is up or gone can land mid-trade.
    ///
    /// **Read directly, not through a predicate expectation.** Waited on as
    /// `isHittable == 1`, the face stayed out of reach for the whole ten
    /// seconds after Done, while `isHittable` read in a loop, and a fresh query
    /// for it, had it back in reach a second after the keyboard went.
    @MainActor
    private func wait(_ element: XCUIElement, hittable: Bool, _ message: String) {
        let deadline = Date().addingTimeInterval(uiTimeout)
        while element.isHittable != hittable, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertEqual(element.isHittable, hittable, message)
    }

    /// Where an element comes to rest, once two readings a beat apart agree —
    /// for a frame the system is still moving, like the slot's as the tab bar
    /// minimizes.
    @MainActor
    private func settledFrame(of element: XCUIElement) -> CGRect {
        var last = element.frame
        for _ in 0..<30 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            let now = element.frame
            if abs(now.minX - last.minX) < 0.5, abs(now.minY - last.minY) < 0.5 { return now }
            last = now
        }
        return last
    }

    // MARK: The chrome

    @MainActor
    func testNewChatEmptiesTheThreadAndTakesTheKeyboard() throws {
        let app = try launch()
        let starters = element(Ids.starters, in: app)
        XCTAssertTrue(starters.waitForExistence(timeout: uiTimeout))
        starters.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element(Ids.answer, in: app).waitForExistence(timeout: turnTimeout))

        let newChat = app.buttons[Ids.clear]
        XCTAssertTrue(newChat.isEnabled, "New Chat is live once there is a thread to end.")
        newChat.tap()

        XCTAssertTrue(element(Ids.starters, in: app).waitForExistence(timeout: uiTimeout),
                      "The first screen comes back.")
        XCTAssertFalse(element(Ids.question, in: app).exists)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: uiTimeout),
                      "The field takes focus, so the keyboard comes up.")
    }

    // MARK: The keyboard

    /// A turn starting takes the keyboard with it, so no answer is read behind
    /// a keyboard. Asserted through the send button; a starter, a follow-up
    /// chip and Try Again all go through the same `isThinking` flip.
    @MainActor
    func testSendingPutsTheKeyboardAway() throws {
        let app = try launch()
        let field = app.textFields[Ids.field]
        XCTAssertTrue(field.waitForExistence(timeout: uiTimeout))
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: uiTimeout))
        field.typeText("How many things do I own in total?")

        app.buttons[Ids.send].tap()
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForNonExistence(timeout: uiTimeout),
            "Sending puts the keyboard away."
        )
        XCTAssertTrue(element(Ids.question, in: app).waitForExistence(timeout: uiTimeout))
    }

    /// A tap on the screen puts the keyboard away — for the reader who tapped
    /// the field and changed their mind.
    ///
    /// By coordinate, low on the left of the column, where there is prose and
    /// no chip: the starters sit centred, and a chip would take the tap as a
    /// send. Not near the root's top — with the keyboard up the column is
    /// bottom-anchored and the navigation bar sits over the scroll view's
    /// first hundred points, where a tap never reaches the gesture.
    @MainActor
    func testTappingTheScreenPutsTheKeyboardAway() {
        let app = launchScripted()
        let field = app.textFields[Ids.field]
        XCTAssertTrue(field.waitForExistence(timeout: uiTimeout))
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: uiTimeout))

        root(app).coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.35)).tap()
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForNonExistence(timeout: uiTimeout),
            "A tap on the screen dismisses the keyboard."
        )
        XCTAssertFalse(element(Ids.question, in: app).exists, "The tap asked nothing.")
    }

    /// The send circle is a dismiss while the field is focused and empty — the
    /// one visible target for putting the keyboard away, in the one state
    /// where an arrow means nothing. Read through its label, the way the stop
    /// state is.
    @MainActor
    func testTheComposerButtonPutsTheKeyboardAway() {
        let app = launchScripted()
        let field = app.textFields[Ids.field]
        XCTAssertTrue(field.waitForExistence(timeout: uiTimeout))
        let button = app.buttons[Ids.send]
        wait(button, label: "Write a question")

        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: uiTimeout))
        wait(button, label: "Dismiss keyboard")

        button.tap()
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForNonExistence(timeout: uiTimeout),
            "The chevron dismisses the keyboard."
        )
        wait(button, label: "Write a question")
    }

    /// The bar's Done, which is the way out the chevron cannot be: with a
    /// draft in the field the composer's circle is a send, so Done is the only
    /// affordance that puts the keyboard away without sending.
    ///
    /// Done shares the bar with the tier caption, which is the tier's name
    /// alone rather than a sentence so that there is room for Done beside it
    /// (`AskTierCaption` has the widths).
    @MainActor
    func testTheDoneItemPutsTheKeyboardAwayWithADraftInTheField() {
        let app = launchScripted()
        let field = app.textFields[Ids.field]
        XCTAssertTrue(field.waitForExistence(timeout: uiTimeout))
        let done = app.buttons[Ids.done]
        XCTAssertFalse(done.exists, "Done belongs to the keyboard, not to the bar at rest.")

        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(done.waitForExistence(timeout: uiTimeout))
        field.typeText("a draft")
        wait(app.buttons[Ids.send], label: "Send")

        done.tap()
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForNonExistence(timeout: uiTimeout),
            "Done puts the keyboard away."
        )
        XCTAssertTrue(done.waitForNonExistence(timeout: uiTimeout))
        XCTAssertEqual(field.value as? String, "a draft", "and it keeps the draft.")
    }

    /// On a phone, whose bars run along the top, History stays in the bar
    /// while the reader types. It leaves only iPhone Duo's strip at the side,
    /// where the keyboard's predictive bar covers the strip's last item
    /// (`AskHistoryItem`), so the test skips where the bars are in the strip.
    /// Beside the Duo's fold it is never there at all: the chats are a pane.
    @MainActor
    func testHistoryStaysInTheBarWhileTheReaderTypesOnAPhone() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        // A domain that keeps its chats, which is what puts History in the bar.
        app.launchArguments = [DemoLaunchArgument.freshHistory, DemoLaunchArgument.scriptedAnswer]
        app.launch()
        XCTAssertTrue(root(app).waitForExistence(timeout: uiTimeout))
        try requireBarsAlongTheTopAndFoot(
            app, "History leaves the strip while the reader types, and beside the fold the chats are a pane instead."
        )
        let history = app.buttons[Ids.history]
        XCTAssertTrue(history.waitForExistence(timeout: uiTimeout), "A domain that keeps its chats has the item.")

        let field = app.textFields[Ids.field]
        XCTAssertTrue(field.waitForExistence(timeout: uiTimeout))
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.buttons[Ids.done].waitForExistence(timeout: uiTimeout), "Done came with the keyboard.")
        XCTAssertTrue(history.exists, "With the bar along the top, typing leaves History where it was.")
    }

    /// The first screen is back where it was once the keyboard has gone —
    /// through the chevron and through Done, the two ways out that never touch
    /// the scroll view, so nothing but the screen itself can put it back.
    ///
    /// `AskInRangeScrollTarget` is what puts it back. Measured without it, this
    /// test failed on its first assertion, the starters 82.7 pt above where
    /// they started.
    ///
    /// Read off the starters' frame, polled until two readings agree: the
    /// keyboard reported gone is not taken to mean its animation has finished.
    ///
    /// Where the column ends, not how it gets there. The column can make its
    /// whole trip in a single frame on the way down and still end exactly at
    /// rest — seen in a host, never reproduced in the demo — so a pass here
    /// says nothing about the motion: `AskKeyboard` has the recordings.
    @MainActor
    func testTheFirstScreenComesBackToRestWhenTheKeyboardLeaves() {
        let app = launchScripted()
        let starters = element(Ids.starters, in: app)
        XCTAssertTrue(starters.waitForExistence(timeout: uiTimeout))
        let rest = settledMinY(of: starters)
        let field = app.textFields[Ids.field]
        let button = app.buttons[Ids.send]
        // The first screen lets its caveat go while it makes room, and only
        // then: a column that moved without it would be the keyboard's inset
        // alone, with the screen never told the keyboard was there.
        let caveat = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Ask reads only what you own")
        ).firstMatch
        XCTAssertTrue(caveat.exists)

        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(caveat.waitForNonExistence(timeout: uiTimeout), "The keyboard's show makes room.")
        wait(button, label: "Dismiss keyboard")
        button.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: uiTimeout))
        XCTAssertEqual(settledMinY(of: starters), rest, accuracy: 1, "The chevron leaves the first screen where it was.")
        XCTAssertTrue(caveat.exists, "Its hide gives the room back.")

        field.tap()
        let done = app.buttons[Ids.done]
        XCTAssertTrue(done.waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(caveat.waitForNonExistence(timeout: uiTimeout), "The second show makes room too.")
        done.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: uiTimeout))
        XCTAssertEqual(settledMinY(of: starters), rest, accuracy: 1, "Done leaves the first screen where it was.")
        XCTAssertTrue(caveat.exists, "Its hide gives the room back.")
    }

    /// Turned on its side, the first screen sets its copy beside its starters,
    /// and the whole bank sits between the bar and the composer at rest. Turned
    /// back, the screen is where it was.
    ///
    /// Stacked, the column wants about 525pt, and an iPhone 18 Pro on its side
    /// has 402 in all, so a stacked first screen puts the starters behind the
    /// composer and off the screen. iPhone Duo's outer display turned is the
    /// same case, and the only one of the Duo's shapes this simulator can make.
    @MainActor
    func testTheFirstScreenFitsAPhoneOnItsSide() throws {
        try requireXCUIDeviceToTurnTheDevice()
        let app = launchScripted()
        let starters = element(Ids.starters, in: app)
        XCTAssertTrue(starters.waitForExistence(timeout: uiTimeout))
        let rest = settledMinY(of: starters)

        // Upright again even when an assertion below stops the test: whatever
        // runs next on this simulator, in any repo, expects a phone upright.
        addTeardownBlock { @MainActor in XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForTurn(of: app, onItsSide: true)
        _ = settledMinY(of: starters)
        let bar = app.navigationBars.firstMatch.frame
        let composer = app.buttons[Ids.send].frame
        // The heading over the bank, not only the bank: it is the top of the
        // taller half, and the first thing the bar's edge would hide.
        let heading = element(Ids.tryAsking, in: app)
        XCTAssertGreaterThanOrEqual(heading.frame.minY, bar.maxY, "Nothing of the bank is under the bar.")
        XCTAssertLessThanOrEqual(starters.frame.maxY, composer.minY, "No starter is behind the composer.")

        XCUIDevice.shared.orientation = .portrait
        waitForTurn(of: app, onItsSide: false)
        XCTAssertEqual(settledMinY(of: starters), rest, accuracy: 1, "Turned back, the first screen is where it was.")
    }

    /// The same in a tab over a host's slot, where the tab bar and the
    /// composer's face hold the foot of the screen: on its side, the bank and
    /// the disclosure sit between the bar and the face at rest.
    ///
    /// The whole column wants 241 pt there and has 206, so it lets its
    /// sentence go and offers two starters
    /// (`AskFirstScreenArrangement.trimsOverSlot`). Upright again, it has its
    /// three.
    @MainActor
    func testTheFirstScreenFitsAPhoneOnItsSideOverTheSlot() throws {
        try requireTheFaceInTheSlot()
        try requireXCUIDeviceToTurnTheDevice()
        let app = launchScripted(DemoLaunchArgument.tabs, DemoLaunchArgument.slot)
        let starters = element(Ids.starters, in: app)
        let face = element(Ids.slotField, in: app)
        XCTAssertTrue(starters.waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(face.waitForExistence(timeout: uiTimeout))
        // Upright first, whichever way the phone was left.
        XCUIDevice.shared.orientation = .portrait
        waitForTurn(of: app, onItsSide: false)
        XCTAssertEqual(starters.buttons.count, 3, "Upright, the bank is whole.")

        addTeardownBlock { @MainActor in XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForTurn(of: app, onItsSide: true)
        let heading = element(Ids.tryAsking, in: app)
        let disclosure = app.staticTexts["Questions are answered on this device."]
        XCTAssertTrue(heading.exists && disclosure.exists, "The heading and the disclosure are the demo's.")
        _ = settledFrame(of: heading)
        _ = settledFrame(of: starters)
        _ = settledFrame(of: disclosure)
        let bar = app.navigationBars.firstMatch.frame
        // The face rides above the tab bar or beside it: the foot is whichever is higher.
        let foot = min(settledFrame(of: face).minY, app.tabBars.firstMatch.frame.minY)
        XCTAssertGreaterThanOrEqual(heading.frame.minY, bar.maxY, "Nothing of the bank is under the bar.")
        XCTAssertLessThanOrEqual(starters.frame.maxY, foot, "No starter is behind the face or the tab bar.")
        XCTAssertLessThanOrEqual(disclosure.frame.maxY, foot, "Nor is the disclosure.")
        XCTAssertEqual(starters.buttons.count, 2, "On its side over the slot, the bank offers two.")

        XCUIDevice.shared.orientation = .portrait
        waitForTurn(of: app, onItsSide: false)
        XCTAssertEqual(starters.buttons.count, 3, "Upright again, the bank is whole.")
    }

    /// Wait for the window to have turned onto its side, or upright again,
    /// before reading a frame after a turn.
    ///
    /// **Turned, not turning.** The settled readings return once two a beat
    /// apart agree, and two taken before the turn begins agree: they are the
    /// frames of the shape the phone is leaving. A run that measured this read
    /// the heading mid-turn and passed.
    ///
    /// It fails where nothing turns the window. On iPhone Duo `XCUIDevice`
    /// changes the orientation the device reports and leaves both displays as
    /// they were, so a test that turns the phone has nothing to read there:
    /// it skips there first (`requireXCUIDeviceToTurnTheDevice()`), or takes
    /// the Duo as it is (`turn(_:onItsSide:)`).
    @MainActor
    private func waitForTurn(of app: XCUIApplication, onItsSide: Bool) {
        let window = app.windows.firstMatch
        let deadline = Date().addingTimeInterval(uiTimeout)
        while (window.frame.width > window.frame.height) != onItsSide, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
        XCTAssertEqual(
            window.frame.width > window.frame.height, onItsSide,
            onItsSide ? "The window turns onto its side." : "The window turns upright again."
        )
    }

    /// An element's top edge once two readings a beat apart agree.
    @MainActor
    private func settledMinY(of element: XCUIElement) -> CGFloat {
        var last = element.frame.minY
        for _ in 0..<30 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            let now = element.frame.minY
            if abs(now - last) < 0.5 { return now }
            last = now
        }
        return last
    }

    /// New Chat is dead until there is a chat to end.
    @MainActor
    func testNewChatIsDisabledOnAnEmptyThread() throws {
        let app = try launch()
        XCTAssertTrue(element(Ids.starters, in: app).waitForExistence(timeout: uiTimeout))
        XCTAssertFalse(app.buttons[Ids.clear].isEnabled)
    }

    /// A grounded answer shows the rows it stood on, and a tile opens the thing
    /// it names — the whole point of `AskItemOpenAction`, and the one test that
    /// checks the opened row is the one the tile named.
    @MainActor
    func testATileOpensTheRowItNames() throws {
        let app = launchScripted()
        let starters = element(Ids.starters, in: app)
        XCTAssertTrue(starters.waitForExistence(timeout: uiTimeout))
        starters.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element(Ids.answer, in: app).waitForExistence(timeout: turnTimeout))

        // The scripted answer always has tiles, so they are asserted rather
        // than skipped when a turn shows none.
        let tiles = element(Ids.results, in: app)
        XCTAssertTrue(tiles.waitForExistence(timeout: uiTimeout), "The scripted answer shows tiles.")
        XCTAssertGreaterThan(tiles.buttons.count, 0)
        // The tile's label is the whole card — "The Long Goodbye, books · 1953"
        // — so the detail's own title is compared as a prefix of it rather than
        // for equality. What is being asserted is that the row which opened is
        // the row the tile named: the id survived the erasure the environment
        // value needs in order to exist at all.
        let tileLabel = tiles.buttons.element(boundBy: 0).label
        tiles.buttons.element(boundBy: 0).tap()
        let detailTitle = app.staticTexts[DemoAccessibility.rowDetailTitle]
        XCTAssertTrue(detailTitle.waitForExistence(timeout: uiTimeout),
                      "Tapping a tile opens something.")
        XCTAssertTrue(tileLabel.hasPrefix(detailTitle.label),
                      "And it is the row the tile named.")
    }

    /// Copy, Copy answer, Edit & Resend and Ask again reach a reader's touch
    /// through the question bubble's menu and nowhere else in AskUI (VoiceOver
    /// has them as the bubble's actions too). The bubble is
    /// selectable as well as menu-bearing, and on iOS 27 `textSelection` is
    /// system selection rather than a callout menu, so a long press on it may
    /// resolve to selection and never reach the menu (`AskQuestionBubble`).
    ///
    /// Driven rather than reasoned about, because which one wins is the
    /// system's decision, and a new release can change it.
    @MainActor
    func testTheQuestionBubblesContextMenuIsReachable() throws {
        let app = try launch()
        let starters = element(Ids.starters, in: app)
        XCTAssertTrue(starters.waitForExistence(timeout: uiTimeout))
        starters.buttons.element(boundBy: 0).tap()

        let question = element(Ids.question, in: app)
        XCTAssertTrue(question.waitForExistence(timeout: uiTimeout))
        question.press(forDuration: 1.2)

        // The menu's own items, by their identifiers.
        let copy = app.buttons[Ids.questionCopy]
        let askAgain = app.buttons[Ids.questionAskAgain]
        XCTAssertTrue(
            copy.waitForExistence(timeout: uiTimeout) || askAgain.waitForExistence(timeout: uiTimeout),
            "A long press on the question bubble must reach the context menu — it is the only "
            + "touch entry point to Copy, Copy answer, Edit & Resend and Ask again anywhere in AskUI."
        )
    }

    // MARK: Entry points

    /// An Ask link puts its question in the composer and the reader in front
    /// of it, and asks nothing. Handed over as a launch argument and routed the
    /// way a link the system opens is; an "Ask about this" button and a
    /// notification action arrive at the same `AskConversationStore.prefill`.
    ///
    /// The apostrophe is on purpose: it is the character the launch-argument
    /// split eats when the question is passed bare.
    @MainActor
    func testAnAskLinkPutsItsQuestionInTheComposer() {
        continueAfterFailure = false
        let question = "What's the oldest thing I have?"
        let app = XCUIApplication()
        app.launchArguments = [
            DemoLaunchArgument.resetThread, DemoLaunchArgument.scriptedAnswer,
            DemoLaunchArgument.prefill, DemoLink.askLink(question: question)
        ]
        app.launch()
        XCTAssertTrue(root(app).waitForExistence(timeout: uiTimeout))

        let field = app.textFields[Ids.field]
        XCTAssertTrue(field.waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: uiTimeout), "The field takes focus.")
        XCTAssertEqual(field.value as? String, question)
        XCTAssertFalse(element(Ids.question, in: app).exists, "A prefill never sends.")
    }

    /// The composer's accessory button runs the host's action. The demo's
    /// prefills a starter, so it lands the way an entry point does: a draft in
    /// a focused field, which is what turns the circle from Dismiss into Send.
    @MainActor
    func testTheComposerAccessoryRunsTheHostsAction() {
        let app = launchScripted()
        let accessory = app.buttons[DemoAccessibility.surprise]
        XCTAssertTrue(accessory.waitForExistence(timeout: uiTimeout))
        accessory.tap()

        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: uiTimeout))
        wait(app.buttons[Ids.send], label: "Send")
        XCTAssertFalse(element(Ids.question, in: app).exists, "The accessory asked nothing.")
    }

    /// A photo waits over the field until the reader sends, goes with the
    /// question it was attached to, and the thread says when the answer read
    /// only the words — which, scripted, with the app answering on its own, it
    /// did.
    @MainActor
    func testAPhotoGoesWithTheQuestionItWasAttachedTo() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            DemoLaunchArgument.resetThread, DemoLaunchArgument.scriptedAnswer, DemoLaunchArgument.photos
        ]
        app.launch()
        XCTAssertTrue(root(app).waitForExistence(timeout: uiTimeout))

        let attach = app.buttons[Ids.attach]
        XCTAssertTrue(attach.waitForExistence(timeout: uiTimeout), "The composer offers a photo.")
        attach.tap()
        let pending = element(Ids.pendingPhoto, in: app)
        XCTAssertTrue(pending.waitForExistence(timeout: uiTimeout), "The photo waits over the field.")
        app.buttons[Ids.removePhoto].tap()
        XCTAssertTrue(pending.waitForNonExistence(timeout: uiTimeout), "Taken back out, it is gone.")

        attach.tap()
        XCTAssertTrue(pending.waitForExistence(timeout: uiTimeout))
        let field = app.textFields[Ids.field]
        field.tap()
        field.typeText("What goes with this?")
        app.buttons[Ids.send].tap()
        XCTAssertTrue(element(Ids.answer, in: app).waitForExistence(timeout: turnTimeout))

        XCTAssertTrue(element(Ids.questionPhoto, in: app).exists, "The photo sits with its question.")
        XCTAssertFalse(pending.exists, "And left the composer with it.")
        XCTAssertTrue(
            element(Ids.photoUnread, in: app).exists,
            "The answer read only the words, and the thread says so."
        )
    }

    // MARK: Under an answer

    /// A pick says why, and offers another. Typed rather than tapped: no
    /// starter asks for a pick.
    @MainActor
    func testAPickSaysWhyAndOffersAnotherPick() {
        let app = launchScripted()
        let field = app.textFields[Ids.field]
        XCTAssertTrue(field.waitForExistence(timeout: uiTimeout))
        field.tap()
        field.typeText("What should I read tonight?")
        app.buttons[Ids.send].tap()
        XCTAssertTrue(element(Ids.answer, in: app).waitForExistence(timeout: turnTimeout))

        XCTAssertTrue(element(Ids.basis, in: app).waitForExistence(timeout: uiTimeout), "A pick says why.")
        XCTAssertTrue(element(DemoAccessibility.spanCard, in: app).exists, "The turn's payload reaches the footer.")
        let another = app.buttons[Ids.anotherPick]
        XCTAssertTrue(another.waitForExistence(timeout: uiTimeout), "A pick offers another.")
        another.tap()

        let questions = app.descendants(matching: .any).matching(identifier: Ids.question)
        let deadline = Date().addingTimeInterval(uiTimeout)
        while questions.count < 2, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertGreaterThanOrEqual(questions.count, 2, "Another pick asks the question again.")
    }

    /// An answer that offers to do something waits for the reader: the card
    /// says what it would do, nothing happens before the tap, and afterwards
    /// the card says what came of it where its buttons were.
    @MainActor
    func testAnOfferWaitsForTheReadersYes() {
        let app = launchScripted()
        let field = app.textFields[Ids.field]
        XCTAssertTrue(field.waitForExistence(timeout: uiTimeout))
        field.tap()
        field.typeText("Can I lend The Peregrine to Sam?")
        app.buttons[Ids.send].tap()
        XCTAssertTrue(element(Ids.answer, in: app).waitForExistence(timeout: turnTimeout))

        let confirm = app.buttons[Ids.proposalConfirm]
        XCTAssertTrue(confirm.waitForExistence(timeout: uiTimeout), "The answer offers to do it.")
        XCTAssertTrue(app.buttons[Ids.proposalDecline].exists, "And offers not to.")
        XCTAssertFalse(element(Ids.proposalOutcome, in: app).exists, "Nothing is done before the tap.")

        confirm.tap()
        let outcome = element(Ids.proposalOutcome, in: app)
        XCTAssertTrue(outcome.waitForExistence(timeout: uiTimeout), "The card says what came of it.")
        XCTAssertEqual(outcome.label, "Marked The Peregrine as lent.", "In the app's words, and nothing else.")
        // Gone, not faded: a button at zero opacity is still one VoiceOver
        // lands on, and still one this query finds.
        XCTAssertTrue(
            app.buttons[Ids.proposalConfirm].waitForNonExistence(timeout: uiTimeout),
            "And there is nothing left to tap."
        )
    }

    // MARK: The assistant: a domain without rows

    /// An assistant's action, offered and taken (`DemoLaunchArgument.assistant`,
    /// scripted). Its answer has no tiles and no count of items under it: the
    /// line under an answer a tool grounded is in the domain's own words. The
    /// card waits for the reader, and what it adds lands in the app's list.
    @MainActor
    func testTheAssistantsOfferIsGroundedInItsOwnWords() {
        let app = launchScripted(DemoLaunchArgument.assistant)
        let field = app.textFields[Ids.field]
        XCTAssertTrue(field.waitForExistence(timeout: uiTimeout))
        field.tap()
        field.typeText("Remind me to water the plants at 6 PM")
        app.buttons[Ids.send].tap()
        XCTAssertTrue(element(Ids.answer, in: app).waitForExistence(timeout: turnTimeout))

        // The card before the line: what an answer brings besides its words
        // arrives in waves, so a line asserted first could be one still on
        // its way, and a check that it isn't a count would pass on nothing.
        let confirm = app.buttons[Ids.proposalConfirm]
        XCTAssertTrue(confirm.waitForExistence(timeout: uiTimeout), "The answer offers the reminder.")
        let evidence = element(Ids.evidence, in: app)
        XCTAssertTrue(evidence.waitForExistence(timeout: uiTimeout), "The answer says what it stood on.")
        XCTAssertEqual(evidence.label, DemoAssistantWords.fromItsTools, "In the domain's words, never a count of items.")
        XCTAssertFalse(element(Ids.results, in: app).exists, "A domain without rows shows no tiles.")

        confirm.tap()
        let outcome = element(Ids.proposalOutcome, in: app)
        XCTAssertTrue(outcome.waitForExistence(timeout: uiTimeout), "The card says what came of it.")
        XCTAssertEqual(outcome.label, "Reminder added: water the plants, at 6 PM.", "In the app's words.")

        app.buttons[DemoAccessibility.reminders].tap()
        let reminder = element(DemoAccessibility.reminder, in: app)
        XCTAssertTrue(reminder.waitForExistence(timeout: uiTimeout), "The app has the reminder.")
        XCTAssertTrue(reminder.label.contains("water the plants"), "The one the card offered.")
    }

    /// An answer nothing grounded says so. The assistant leaves the line to
    /// AskKit there, so it reads "Not from this app's data" where a count
    /// would stand, and the answer offers nothing.
    @MainActor
    func testTheAssistantsAnswerFromTheModelAloneSaysItIsntFromTheAppsData() {
        let app = launchScripted(DemoLaunchArgument.assistant)
        let field = app.textFields[Ids.field]
        XCTAssertTrue(field.waitForExistence(timeout: uiTimeout))
        field.tap()
        field.typeText("Suggest a name for a houseplant")
        app.buttons[Ids.send].tap()
        XCTAssertTrue(element(Ids.answer, in: app).waitForExistence(timeout: turnTimeout))

        let evidence = element(Ids.evidence, in: app)
        XCTAssertTrue(evidence.waitForExistence(timeout: uiTimeout), "The answer says what it stood on.")
        // The catalog's English, with its typographic apostrophe: the key's
        // straight one is never what the screen draws.
        XCTAssertEqual(evidence.label, "Not from this app\u{2019}s data", "Nothing grounded it, and the line says so.")
        // Tiles arrive before the line, so none by now is none at all. A card
        // arrives after it, so its absence is waited out.
        XCTAssertFalse(element(Ids.results, in: app).exists, "It shows no tiles.")
        XCTAssertFalse(app.buttons[Ids.proposalConfirm].waitForExistence(timeout: 2), "And offers nothing.")
    }

    /// The reader's chats, wherever the screen keeps them: the pane beside
    /// iPhone Duo's fold, where the bar has no History, or the sheet History
    /// opens everywhere else. Which one is there is the screen's to decide,
    /// so the test reads it rather than asking which device it is on.
    @MainActor
    private func openTheChats(in app: XCUIApplication) -> (list: XCUIElement, isPane: Bool) {
        let pane = element(Ids.historyPane, in: app)
        let history = app.buttons[Ids.history]
        let deadline = Date().addingTimeInterval(uiTimeout)
        while !pane.exists, !history.exists, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        if pane.exists { return (pane, true) }
        history.tap()
        return (element(Ids.historyList, in: app), false)
    }

    /// New Chat files the chat, and the list of chats opens it again: the
    /// sheet History opens, or beside a fold the pane.
    @MainActor
    func testAnEarlierChatCanBeOpenedAgain() {
        continueAfterFailure = false
        let app = XCUIApplication()
        // A domain that keeps its chats, starting from none: without the clean
        // slate the list holds whatever the run before this one filed.
        app.launchArguments = [DemoLaunchArgument.freshHistory, DemoLaunchArgument.scriptedAnswer]
        app.launch()
        XCTAssertTrue(root(app).waitForExistence(timeout: uiTimeout))

        let question = "What should I read tonight?"
        let field = app.textFields[Ids.field]
        XCTAssertTrue(field.waitForExistence(timeout: uiTimeout))
        field.tap()
        field.typeText(question)
        app.buttons[Ids.send].tap()
        XCTAssertTrue(element(Ids.answer, in: app).waitForExistence(timeout: turnTimeout))

        app.buttons[Ids.clear].tap()
        let questions = app.descendants(matching: .any).matching(identifier: Ids.question)
        XCTAssertTrue(questions.firstMatch.waitForNonExistence(timeout: uiTimeout), "New Chat emptied the thread.")

        let chats = openTheChats(in: app)
        XCTAssertTrue(chats.list.waitForExistence(timeout: uiTimeout), "The list of chats came up.")
        let row = chats.list.buttons.matching(NSPredicate(format: "label CONTAINS %@", question)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: uiTimeout), "The chat New Chat put away is listed.")
        row.tap()

        if chats.isPane {
            XCTAssertTrue(chats.list.exists, "Beside the fold the pane stays when a chat is chosen.")
        } else {
            XCTAssertTrue(chats.list.waitForNonExistence(timeout: uiTimeout), "The list goes when a chat is chosen.")
        }
        XCTAssertTrue(questions.firstMatch.waitForExistence(timeout: uiTimeout), "The chosen chat is the thread again.")
    }

    /// Delete All Chats asks first, then leaves nothing to go back to: not the
    /// chat New Chat filed, and not the one on screen. From the sheet History
    /// opens, or beside a fold from the pane, which goes with the chats.
    @MainActor
    func testEveryChatCanBeDeleted() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [DemoLaunchArgument.freshHistory, DemoLaunchArgument.scriptedAnswer]
        app.launch()
        XCTAssertTrue(root(app).waitForExistence(timeout: uiTimeout))

        let field = app.textFields[Ids.field]
        let questions = app.descendants(matching: .any).matching(identifier: Ids.question)
        for question in ["What should I read tonight?", "What have I lent out?"] {
            if questions.firstMatch.exists {
                app.buttons[Ids.clear].tap()
                XCTAssertTrue(questions.firstMatch.waitForNonExistence(timeout: uiTimeout), "New Chat filed the first chat.")
            }
            XCTAssertTrue(field.waitForExistence(timeout: uiTimeout))
            field.tap()
            field.typeText(question)
            app.buttons[Ids.send].tap()
            XCTAssertTrue(element(Ids.answer, in: app).waitForExistence(timeout: turnTimeout))
        }

        let chats = openTheChats(in: app)
        XCTAssertTrue(chats.list.waitForExistence(timeout: uiTimeout), "The list of chats came up.")
        app.buttons[Ids.historyDeleteAll].tap()

        // The dialog's own button, not the bar's that opened it. The first
        // match, because on the iOS 27.2 simulator two buttons answer to the
        // identifier the app sets once, on the dialog's button: "Multiple
        // matching elements found" without it.
        let confirm = app.buttons[Ids.historyDeleteAllConfirm].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: uiTimeout), "Deleting every chat asks first.")
        confirm.tap()

        XCTAssertTrue(chats.list.waitForNonExistence(timeout: uiTimeout), "The list closes with nothing left in it.")
        XCTAssertTrue(questions.firstMatch.waitForNonExistence(timeout: uiTimeout), "The chat on screen went too.")
        if chats.isPane {
            // Beside the fold the bar has no History to open: with nothing to
            // list, the pane stays away.
            XCTAssertFalse(chats.list.waitForExistence(timeout: 3), "Nothing is left to go back to.")
        } else {
            app.buttons[Ids.history].tap()
            XCTAssertTrue(
                app.staticTexts["No earlier chats"].waitForExistence(timeout: uiTimeout), "Nothing is left to go back to."
            )
        }
    }

    /// Beside a fold, before the reader has a chat, the first screen takes
    /// both panes: what Ask is on the leading side, and what to ask on the
    /// trailing side, over the composer
    /// (`AskFirstScreenArrangement.takesBothPanes`). Asked a question, the
    /// leading pane is the chats'.
    ///
    /// Around the demo's stand-in fold (`DemoLaunchArgument.fold`), on a phone
    /// on its side: the arrangement, and nothing else of iPhone Duo.
    ///
    /// **The fold is where the conversation's pane begins**, `ask.root`'s
    /// leading edge. The stand-in runs through the middle of the screen's own
    /// view, and on a phone that is the window's middle: 437.3 against 437 on
    /// an iPhone 18 Pro on its side. On iPhone Duo, taken open on its side as
    /// it was left (`turn(_:onItsSide:)`), the strip takes the window's last
    /// 84 pt, and the stand-in is at 434 where the window's middle is 475.5.
    @MainActor
    func testBesideAFoldWithNoChatsTheFirstScreenTakesBothPanes() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        // A domain that keeps its chats, starting from none.
        app.launchArguments = [
            DemoLaunchArgument.freshHistory, DemoLaunchArgument.scriptedAnswer, DemoLaunchArgument.fold, "book"
        ]
        app.launch()
        XCTAssertTrue(root(app).waitForExistence(timeout: uiTimeout))

        try turn(app, onItsSide: true)

        let starters = element(Ids.starters, in: app)
        let headline = app.staticTexts["Ask about your things"]
        XCTAssertTrue(starters.waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(headline.waitForExistence(timeout: uiTimeout), "The headline is the demo's.")
        let fold = settledFrame(of: root(app)).minX
        let bank = settledFrame(of: starters)
        XCTAssertLessThanOrEqual(headline.frame.maxX, fold, "What Ask is keeps to the leading side of the fold.")
        XCTAssertGreaterThanOrEqual(bank.minX, fold, "What to ask keeps to the trailing side,")
        XCTAssertGreaterThanOrEqual(app.buttons[Ids.send].frame.minX, fold, "and so does the composer.")
        XCTAssertFalse(element(Ids.historyPane, in: app).exists, "With no chats, the pane lists none.")

        starters.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element(Ids.answer, in: app).waitForExistence(timeout: turnTimeout))
        XCTAssertTrue(
            element(Ids.historyPane, in: app).waitForExistence(timeout: uiTimeout),
            "Asked a question, the leading pane is the chats'."
        )
        XCTAssertTrue(headline.waitForNonExistence(timeout: uiTimeout), "And the first screen is gone from it.")
    }

    /// Beside iPhone Duo's fold the reader's chats stay on screen in a pane of
    /// their own: every chat newest first, the open one marked, and an earlier
    /// one opened beside the list, where the mark moves to it and no row moves.
    ///
    /// Around a stand-in fold (`DemoLaunchArgument.fold`), with the phone on
    /// its side so that each side of the fold is wide enough for a pane:
    /// upright, a phone's halves are too narrow and the screen stays whole.
    /// The arrangement alone. The Duo's bar strip and its sizes are for the
    /// Duo simulator to show.
    @MainActor
    func testBesideAFoldTheChatsStayOnScreenWithTheOpenOneMarked() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            DemoLaunchArgument.freshHistory, DemoLaunchArgument.scriptedAnswer, DemoLaunchArgument.fold, "book"
        ]
        app.launch()
        XCTAssertTrue(root(app).waitForExistence(timeout: uiTimeout))
        let pane = element(Ids.historyPane, in: app)
        XCTAssertFalse(pane.exists, "Upright, neither side of the fold is wide enough for a pane.")

        // Two chats, filed upright, where the keyboard leaves the field room.
        let earlierQuestion = "What should I read tonight?"
        let openQuestion = "What have I lent out?"
        let field = app.textFields[Ids.field]
        let questions = app.descendants(matching: .any).matching(identifier: Ids.question)
        for question in [earlierQuestion, openQuestion] {
            if questions.firstMatch.exists {
                app.buttons[Ids.clear].tap()
                XCTAssertTrue(questions.firstMatch.waitForNonExistence(timeout: uiTimeout), "New Chat filed the first chat.")
            }
            XCTAssertTrue(field.waitForExistence(timeout: uiTimeout))
            field.tap()
            field.typeText(question)
            app.buttons[Ids.send].tap()
            XCTAssertTrue(element(Ids.answer, in: app).waitForExistence(timeout: turnTimeout))
        }

        addTeardownBlock { @MainActor in XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForTurn(of: app, onItsSide: true)
        XCTAssertTrue(pane.waitForExistence(timeout: uiTimeout), "On its side, the chats take the leading pane.")
        XCTAssertFalse(app.buttons[Ids.history].exists, "They are on screen, so the bar has no button for them.")

        let open = element(Ids.historyCurrent, in: app)
        XCTAssertTrue(open.waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(open.label.contains(openQuestion), "The chat on screen is a row of the list,")
        XCTAssertTrue(open.isSelected, "marked as the open one.")
        let earlier = pane.buttons.matching(NSPredicate(format: "label CONTAINS %@", earlierQuestion)).firstMatch
        XCTAssertTrue(earlier.waitForExistence(timeout: uiTimeout), "The chat New Chat put away is listed,")
        let place = settledFrame(of: earlier).minY
        XCTAssertGreaterThan(place, open.frame.minY, "under the newer one.")

        earlier.tap()
        wait(open, labelContaining: earlierQuestion)
        XCTAssertEqual(settledFrame(of: open).minY, place, accuracy: 1, "Opened, it is marked where it was.")
        XCTAssertTrue(pane.exists, "The pane stays.")
        // The bubble's label says whose words they are; the words are its value.
        let shown = questions.matching(NSPredicate(format: "value CONTAINS %@", earlierQuestion)).firstMatch
        XCTAssertTrue(shown.waitForExistence(timeout: uiTimeout), "And the chat is the thread beside it.")
    }

    /// Around iPhone Duo's own fold, open on its side, by touch: a question
    /// asked from the first screen's two halves, New Chat, an earlier chat
    /// opened from the pane, and Delete All Chats.
    ///
    /// It takes the device as it finds it, and skips wherever a question asked
    /// leaves no pane of chats: every device but the Duo open on its side.
    /// Nothing turns or opens the Duo from a test, so set the pose first. The
    /// stand-in fold's two tests above pin the arrangement on a phone.
    @MainActor
    func testAroundTheDuosOwnFoldThePanesTakeTheReadersTouch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        // A domain that keeps its chats, starting from none.
        app.launchArguments = [DemoLaunchArgument.freshHistory, DemoLaunchArgument.scriptedAnswer]
        app.launch()
        XCTAssertTrue(root(app).waitForExistence(timeout: uiTimeout))
        let pane = element(Ids.historyPane, in: app)
        let starters = element(Ids.starters, in: app)
        let headline = app.staticTexts["Ask about your things"]
        let questions = app.descendants(matching: .any).matching(identifier: Ids.question)
        XCTAssertTrue(starters.waitForExistence(timeout: uiTimeout))
        XCTAssertFalse(pane.exists, "With no chats, the pane lists none.")

        let starter = starters.buttons.element(boundBy: 0)
        let earlierQuestion = starter.label
        starter.tap()
        XCTAssertTrue(element(Ids.answer, in: app).waitForExistence(timeout: turnTimeout), "A starter asks its question.")
        try XCTSkipUnless(
            pane.waitForExistence(timeout: uiTimeout),
            "No fold with room for two panes: this is for iPhone Duo open on its side."
        )
        let fold = settledFrame(of: pane).maxX
        XCTAssertTrue(headline.waitForNonExistence(timeout: uiTimeout), "Asked a question, the leading pane is the chats'.")
        XCTAssertFalse(app.buttons[Ids.history].exists, "They are on screen, so the bar has no button for them.")
        XCTAssertGreaterThanOrEqual(app.buttons[Ids.send].frame.minX, fold, "The composer keeps to the conversation's pane.")

        app.buttons[Ids.clear].tap()
        XCTAssertTrue(questions.firstMatch.waitForNonExistence(timeout: uiTimeout), "New Chat emptied the thread.")
        XCTAssertTrue(pane.exists, "The chats stay beside it,")
        XCTAssertGreaterThanOrEqual(settledFrame(of: starters).minX, fold, "and the first screen is in the conversation's pane:")
        // New Chat takes the keyboard, and in a window as short as the inner
        // display on its side the first screen lets its headline go while the
        // keyboard is up. Done brings it back.
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: uiTimeout))
        app.buttons[Ids.done].tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: uiTimeout))
        XCTAssertTrue(headline.waitForExistence(timeout: uiTimeout))
        XCTAssertGreaterThanOrEqual(headline.frame.minX, fold, "the whole of it, with the keyboard put away.")

        let openQuestion = "What have I lent out?"
        let field = app.textFields[Ids.field]
        XCTAssertTrue(field.waitForExistence(timeout: uiTimeout))
        field.tap()
        field.typeText(openQuestion)
        app.buttons[Ids.send].tap()
        XCTAssertTrue(element(Ids.answer, in: app).waitForExistence(timeout: turnTimeout))

        let open = element(Ids.historyCurrent, in: app)
        XCTAssertTrue(open.waitForExistence(timeout: uiTimeout))
        XCTAssertTrue(open.label.contains(openQuestion), "The chat on screen is a row of the list.")
        let earlier = pane.buttons.matching(NSPredicate(format: "label CONTAINS %@", earlierQuestion)).firstMatch
        XCTAssertTrue(earlier.waitForExistence(timeout: uiTimeout), "The chat New Chat put away is listed,")
        let place = settledFrame(of: earlier).minY
        XCTAssertGreaterThan(place, open.frame.minY, "under the newer one.")
        earlier.tap()
        wait(open, labelContaining: earlierQuestion)
        XCTAssertEqual(settledFrame(of: open).minY, place, accuracy: 1, "Opened, it is marked where it was.")
        let shown = questions.matching(NSPredicate(format: "value CONTAINS %@", earlierQuestion)).firstMatch
        XCTAssertTrue(shown.waitForExistence(timeout: uiTimeout), "And the chat is the thread beside it.")

        app.buttons[Ids.historyDeleteAll].tap()
        // The dialog's own button, not the pane's that opened it, and the
        // first match, for the reason `testEveryChatCanBeDeleted` gives.
        let confirm = app.buttons[Ids.historyDeleteAllConfirm].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: uiTimeout), "Deleting every chat asks first.")
        confirm.tap()
        XCTAssertTrue(pane.waitForNonExistence(timeout: uiTimeout), "With nothing left to list, the pane goes,")
        XCTAssertTrue(headline.waitForExistence(timeout: uiTimeout))
        XCTAssertLessThanOrEqual(headline.frame.maxX, fold, "and the first screen takes both panes again.")
        XCTAssertGreaterThanOrEqual(settledFrame(of: starters).minX, fold)
    }

    /// Wait for an element's label to contain `text`.
    @MainActor
    private func wait(_ element: XCUIElement, labelContaining text: String) {
        let matched = expectation(
            for: NSPredicate(format: "label CONTAINS %@", text), evaluatedWith: element
        )
        wait(for: [matched], timeout: uiTimeout)
    }

    /// A starter the reader does not want can be turned down, and it goes.
    @MainActor
    func testAStarterCanBeTurnedDown() {
        let app = launchScripted()
        let starters = element(Ids.starters, in: app)
        XCTAssertTrue(starters.waitForExistence(timeout: uiTimeout))
        let first = starters.buttons.element(boundBy: 0)
        let label = first.label
        first.press(forDuration: 1.2)

        let decline = app.buttons[Ids.declineSuggestion]
        XCTAssertTrue(decline.waitForExistence(timeout: uiTimeout), "A long press offers to turn it down.")
        decline.tap()
        XCTAssertTrue(starters.buttons[label].waitForNonExistence(timeout: uiTimeout), "The starter goes.")
        XCTAssertFalse(element(Ids.question, in: app).exists, "Turning a starter down asks nothing.")
    }

    /// The thumbs, on a Debug build, where `AskDiagnostics.isEnabled` holds as
    /// it does on TestFlight. The chosen thumb reads as selected.
    @MainActor
    func testAnAnswerCanBeRated() {
        let app = launchScripted()
        let starters = element(Ids.starters, in: app)
        XCTAssertTrue(starters.waitForExistence(timeout: uiTimeout))
        starters.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element(Ids.answer, in: app).waitForExistence(timeout: turnTimeout))

        let helpful = app.buttons[Ids.feedbackPositive]
        XCTAssertTrue(helpful.waitForExistence(timeout: uiTimeout))
        XCTAssertFalse(helpful.isSelected)
        helpful.tap()
        let selected = expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: helpful)
        wait(for: [selected], timeout: uiTimeout)
        XCTAssertFalse(app.buttons[Ids.feedbackNegative].isSelected)
    }

    /// At the largest text size the answer's footer keeps its line whole.
    ///
    /// Beside the thumbs the evidence line was left a character's width, and
    /// broke to a letter a line: many times taller than wide. With the thumbs
    /// under it, the line has the column.
    ///
    /// The size goes in as a launch argument, so the device's own setting
    /// stays as it was.
    @MainActor
    func testTheFooterKeepsItsLineWholeAtTheLargestTextSize() throws {
        let app = launchScripted("-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL")
        // Upright, whichever way the phone was left. On its side the column
        // is wide enough for the line beside the thumbs at any text size, so
        // the footer as it was passes there too: run on a phone another
        // session had left in landscape, this test passed against the layout
        // it exists to catch. iPhone Duo, which no test turns, runs it only
        // where it was left upright, and skips it on its side.
        try turn(app, onItsSide: false)

        let starters = element(Ids.starters, in: app)
        XCTAssertTrue(starters.waitForExistence(timeout: uiTimeout))
        starters.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element(Ids.answer, in: app).waitForExistence(timeout: turnTimeout))

        let helpful = app.buttons[Ids.feedbackPositive]
        let notHelpful = app.buttons[Ids.feedbackNegative]
        XCTAssertTrue(helpful.waitForExistence(timeout: uiTimeout))
        let evidence = element(Ids.evidence, in: app)
        XCTAssertTrue(evidence.waitForExistence(timeout: uiTimeout), "The answer says how much it read.")

        XCTAssertGreaterThan(
            evidence.frame.width, evidence.frame.height,
            "The line reads across, not a letter a line."
        )
        XCTAssertFalse(evidence.frame.intersects(helpful.frame), "The thumbs are clear of the line.")
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(helpful.frame.minX, window.minX, "Both thumbs are inside the window.")
        XCTAssertLessThanOrEqual(notHelpful.frame.maxX, window.maxX, "Both thumbs are inside the window.")
    }

    // MARK: The audit

    /// Apple's own checks, on the first screen the demo opens to in light: the
    /// ready one, or the can't-serve one where there is no model.
    ///
    /// Outside `launch()`'s model-availability skip on purpose: contrast, hit
    /// regions and element descriptions are properties of the layout, not of
    /// whether a model answered, so this arm has to run on a machine where the
    /// on-device model is unavailable. It is also the only test here that
    /// catches a `.tertiary` string too faint to read, a target under 44pt or an
    /// unlabelled button — for every host at once, since they share this
    /// screen.
    @MainActor
    func testTheScreenPassesApplesAccessibilityAudit() throws {
        try auditTheFirstScreen(in: .light)
    }

    /// The same audit in dark, which reads its own pixels: a gray that clears
    /// it on a light ground says nothing of one on black.
    @MainActor
    func testTheScreenPassesApplesAccessibilityAuditInDark() throws {
        try auditTheFirstScreen(in: .dark)
    }

    /// The audit, with the device in `appearance` for the run and back as it was
    /// after, whether the audit passes or not.
    ///
    /// **Contrast is a call of its own.** In one call with `.dynamicType` and
    /// another check the audit fails the disclosure line in both appearances and "Try asking" in
    /// light at every strength of their gray, #3C3C43 at 100% on white (10.9:1)
    /// and #EBEBF5 at 100% on black (17.7:1) included, so those verdicts don't
    /// read the color. On its own call it does: in light it fails the first
    /// screen's grays at 50%, nearly passes them at 60% and 68% and passes
    /// 76% (`askDeemphasizedText`), and in dark it passes `.secondary`.
    @MainActor
    private func auditTheFirstScreen(in appearance: XCUIDevice.Appearance) throws {
        continueAfterFailure = false
        use(appearance)
        let app = XCUIApplication()
        app.launchArguments = [DemoLaunchArgument.resetThread]
        app.launch()
        // By identifier alone, for the reason `launch()` spells out: which XCUI
        // type `ask.root` lands on moves with the layout.
        XCTAssertTrue(root(app).waitForExistence(timeout: uiTimeout), "The screen came up.")

        // Chip rows, whose glass capsules the contrast audit misreads — see the
        // handler below. By identifier alone, the rule `launch()` spells out:
        // the bank is an explicit container (`AskChipRow` says why), and a
        // query by type that stopped finding it would empty this list, unmask
        // the capsules' false positives, and fail the audit on a change that
        // broke nothing.
        let chipRows = chipRowFrames(in: app)

        try app.performAccessibilityAudit(for: .contrast) { issue in
            // A measured false positive, suppressed narrowly rather than by
            // dropping `.contrast` from the audit.
            //
            // The audit reads an element's contrast from its screenshot over
            // the element's RECTANGULAR bounds. A glass capsule does not fill
            // those bounds: its rounded corners are transparent, and they
            // composite to near-black. So the comparison it makes on a chip is
            // the capsule fill against its own corners — #202020 vs #000000,
            // which is 1.29:1 and fails.
            //
            // The contrast a reader actually sees is the label against the
            // capsule: #FFFFFF on #202020, measured off this same element
            // screenshot at 16.29:1, against a 4.5:1 bar. Nothing is wrong with
            // the chip.
            //
            // Scoped to contrast issues on elements inside a chip row, so a
            // real contrast failure anywhere else on the screen still fails
            // this test — which is the whole point of the arm.
            guard issue.auditType == .contrast, let element = issue.element else { return false }
            let frame = element.frame
            return chipRows.contains { $0.intersects(frame) }
        }

        try app.performAccessibilityAudit(for: Self.everyCheckButContrast)
    }

    /// Every check the audit has, contrast apart: the default `.all` but for
    /// the check that runs in a call of its own (`auditTheFirstScreen`). On
    /// iOS that includes `.textClipped` and `.trait`.
    private static let everyCheckButContrast = XCUIAccessibilityAuditType.all.subtracting(.contrast)

    /// The frames of the chip rows on screen, whose glass capsules the contrast
    /// audit misreads (`auditTheFirstScreen` has the measurement), found by
    /// identifier alone for the reason given there.
    @MainActor
    private func chipRowFrames(in app: XCUIApplication) -> [CGRect] {
        [Ids.starters, Ids.followUps, Ids.coaching]
            .map { element($0, in: app) }
            .filter(\.exists)
            .map(\.frame)
    }

    // MARK: Apple's audit on a thread

    /// A thread with a scripted answer and its tiles, by Apple's audit: every
    /// check but contrast, then contrast alone, in light. The first screen's
    /// audit never saw a turn: the question bubble on its fill, the answer, the
    /// tiles, the evidence line.
    @MainActor
    func testAnAnswerWithTilesPassesApplesAccessibilityAudit() throws {
        try auditTheThread(.answerWithTiles, in: .light)
    }

    /// The same, in dark, where the bubble's words are white on the accent.
    @MainActor
    func testAnAnswerWithTilesPassesApplesAccessibilityAuditInDark() throws {
        try auditTheThread(.answerWithTiles, in: .dark)
    }

    /// A turn that ended before its first word, with Try Again under the line
    /// that says so, by the same audit, in light.
    @MainActor
    func testAFailureWithTryAgainPassesApplesAccessibilityAudit() throws {
        try auditTheThread(.failureWithTryAgain, in: .light)
    }

    /// The same, in dark.
    @MainActor
    func testAFailureWithTryAgainPassesApplesAccessibilityAuditInDark() throws {
        try auditTheThread(.failureWithTryAgain, in: .dark)
    }

    /// The thread states the audit is run on.
    private enum AuditedThread {
        /// The scripted answer: prose, two tiles and the evidence line.
        case answerWithTiles
        /// A turn held in flight and stopped before its first word: the line
        /// that says so, and Try Again. No model is needed for either.
        case failureWithTryAgain
    }

    /// `state` on screen in `appearance`, audited in two calls: every check
    /// but contrast, then contrast alone, which can't share a call
    /// (`auditTheFirstScreen`). One measured false positive is let through,
    /// on the elements it was measured on and nothing else: a partial Dynamic
    /// Type verdict below the answer's words (`grewOffScreen(_:below:)`).
    /// Contrast lets nothing through: the thread's chips and Try Again are
    /// fills, not the glass capsules whose corners the audit misreads on the
    /// first screen.
    @MainActor
    private func auditTheThread(_ state: AuditedThread, in appearance: XCUIDevice.Appearance) throws {
        continueAfterFailure = false
        use(appearance)
        let app: XCUIApplication
        switch state {
        case .answerWithTiles:
            app = launchScripted()
            let starters = element(Ids.starters, in: app)
            XCTAssertTrue(starters.waitForExistence(timeout: uiTimeout))
            starters.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(element(Ids.answer, in: app).waitForExistence(timeout: turnTimeout), "The answer came.")
            XCTAssertTrue(element(Ids.results, in: app).waitForExistence(timeout: uiTimeout), "With its tiles.")
            XCTAssertTrue(element(Ids.evidence, in: app).waitForExistence(timeout: uiTimeout), "And its evidence line.")
        case .failureWithTryAgain:
            app = XCUIApplication()
            app.launchArguments = [DemoLaunchArgument.resetThread, DemoLaunchArgument.holdTurn]
            app.launch()
            XCTAssertTrue(root(app).waitForExistence(timeout: uiTimeout))
            let starters = element(Ids.starters, in: app)
            XCTAssertTrue(starters.waitForExistence(timeout: uiTimeout))
            starters.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(element(Ids.thinking, in: app).waitForExistence(timeout: uiTimeout), "The turn is held.")
            app.buttons[Ids.send].tap()   // reads "Cancel" here
            XCTAssertTrue(app.buttons[Ids.retry].waitForExistence(timeout: uiTimeout), "Try Again is offered.")
        }
        XCTAssertTrue(element(Ids.question, in: app).exists, "The question is on the thread.")
        // What an answer brings arrives in waves within 600 ms (`askArrival`),
        // and an audit of a piece still coming up out of its blur reads a
        // contrast no reader is left with.
        Thread.sleep(forTimeInterval: 1)

        let answer = element(Ids.answer, in: app)
        let foot = answer.exists ? answer.frame.maxY : .infinity
        try app.performAccessibilityAudit(for: Self.everyCheckButContrast) { issue in
            Self.grewOffScreen(issue, below: foot)
        }
        try app.performAccessibilityAudit(for: .contrast)
    }

    /// Whether `issue` is the Dynamic Type check's "partially unsupported" on
    /// an element that starts below `foot`, the bottom of the answer's words.
    ///
    /// **The audit grows the text in place, and the thread keeps its top.**
    /// Measured with `simctl ui content_size` on a settled scripted answer:
    /// at the largest size the answer's words fill the screen and the evidence
    /// line, the payload card and the confirmation card's buttons go under the
    /// composer and off the bottom, where the audit can't see them grow. They
    /// do grow: launched at that size, with the thread following its foot,
    /// the evidence line is 51.3 pt tall where it is 14.3 at the default, and
    /// the payload card's "1939–2023" 58.7 where it is 18. So only a partial
    /// verdict is let through, and only below the answer; an element that
    /// doesn't grow at all is "unsupported", which fails anywhere, and so does
    /// a partial verdict on the question or the answer itself.
    @MainActor
    private static func grewOffScreen(_ issue: XCUIAccessibilityAuditIssue, below foot: CGFloat) -> Bool {
        guard issue.auditType == .dynamicType,
              issue.compactDescription.localizedCaseInsensitiveContains("partially"),
              let element = issue.element else { return false }
        return element.frame.minY >= foot
    }

    /// The device in `appearance` for the rest of the test, and back as it was
    /// after, whether the test passes or not.
    @MainActor
    private func use(_ appearance: XCUIDevice.Appearance) {
        let device = XCUIDevice.shared
        let before = device.appearance
        device.appearance = appearance
        addTeardownBlock { @MainActor in device.appearance = before }
    }

    /// The confirmation card, by Apple's audit: every check but contrast, then
    /// contrast alone, in light.
    @MainActor
    func testTheConfirmationCardPassesApplesAccessibilityAudit() throws {
        try auditTheConfirmationCard(in: .light)
    }

    /// The same, in dark.
    @MainActor
    func testTheConfirmationCardPassesApplesAccessibilityAuditInDark() throws {
        try auditTheConfirmationCard(in: .dark)
    }

    /// The card's two buttons: the confirm button's words on the host's accent
    /// and "Not now" on its gray, and every other check on the thread around
    /// them, in a call of their own (`auditTheThread`).
    ///
    /// **The confirm button's words are black on the demo's accent**, the
    /// system blue, where white falls under text's 4.5:1: 3.52:1 in light and
    /// 3.23:1 in dark, to black's 5.97:1 and 6.49:1 (`AskOnAccentLabel`). The
    /// audit read white there as "nearly passed", and passes black in both
    /// appearances, so it lets nothing through on the card: the confirm
    /// button and "Not now" are held to it as they are.
    @MainActor
    private func auditTheConfirmationCard(in appearance: XCUIDevice.Appearance) throws {
        continueAfterFailure = false
        use(appearance)
        let app = launchScripted()
        let field = app.textFields[Ids.field]
        XCTAssertTrue(field.waitForExistence(timeout: uiTimeout))
        field.tap()
        field.typeText("Can I lend The Peregrine to Sam?")
        app.buttons[Ids.send].tap()
        XCTAssertTrue(element(Ids.answer, in: app).waitForExistence(timeout: turnTimeout))
        XCTAssertTrue(app.buttons[Ids.proposalConfirm].waitForExistence(timeout: uiTimeout), "The answer offers to do it.")
        XCTAssertTrue(app.buttons[Ids.proposalDecline].exists, "And offers not to.")
        // The card arrives last of the answer's waves (`auditTheThread`).
        Thread.sleep(forTimeInterval: 1)

        let foot = element(Ids.answer, in: app).frame.maxY
        try app.performAccessibilityAudit(for: Self.everyCheckButContrast) { issue in
            Self.grewOffScreen(issue, below: foot)
        }
        try app.performAccessibilityAudit(for: .contrast)
    }

    /// The nothing-to-ask screen's button, by Apple's contrast audit alone, in
    /// light.
    @MainActor
    func testTheNothingToAskButtonPassesTheContrastAudit() throws {
        try auditTheNothingToAskButton(in: .light)
    }

    /// The same, in dark.
    @MainActor
    func testTheNothingToAskButtonPassesTheContrastAuditInDark() throws {
        try auditTheNothingToAskButton(in: .dark)
    }

    /// The screen with nothing to ask about and a button to add a first item,
    /// which needs a model to show (`launch()` skips without one: with none
    /// the first screen says why instead).
    ///
    /// **The button's words are black on the demo's accent**, the system blue,
    /// where white falls under text's 4.5:1 (`AskOnAccentLabel`). In dark the
    /// audit read white, 3.23:1 on the accent's #0091FF, as "nearly passed",
    /// and passes black, 6.49:1 on that accent, so in dark it lets nothing
    /// through.
    ///
    /// **In light the audit says "failed", and that verdict doesn't read the
    /// label.** The button is a glass capsule, and its element screenshot had
    /// the label white on a fill of #0087FD, 3.57:1, about the confirmation
    /// card's flat button's 3.52:1, which "nearly passed". The same button with
    /// the black label it draws now, 5.97:1 on that fill in the screenshot's
    /// own pixels, failed too, while in a flat `.borderedProminent` fill, white
    /// corners and all, white nearly passed and black passed. So what fails is
    /// the glass's shaded fill and rim, not what a reader sees, and the light
    /// verdict on this one element is let through whatever it says.
    @MainActor
    private func auditTheNothingToAskButton(in appearance: XCUIDevice.Appearance) throws {
        use(appearance)
        let app = try launch(DemoLaunchArgument.emptyLibrary, "button")
        XCTAssertTrue(app.buttons[Ids.nothingAction].waitForExistence(timeout: uiTimeout), "The screen offers its button.")

        try app.performAccessibilityAudit(for: .contrast) { issue in
            appearance == .light && issue.element?.identifier == Ids.nothingAction
        }
    }

    /// The composer with nothing in it, by Apple's contrast audit alone: the
    /// placeholder, the host's hint, drawn on the capsule's accent tint, and
    /// the accessory button's glyph beside it.
    ///
    /// **The one measurement of the glass AskUI can't make itself.** What the
    /// placeholder is drawn in is chosen from an estimate of the tinted glass
    /// as a flat blend (`AskGlassForeground`), and Liquid Glass isn't one.
    /// This reads the pixels. Scoped to issues on the composer's own elements,
    /// so it says nothing new about the rest of the screen, which the audit
    /// above covers.
    @MainActor
    func testTheEmptyComposerPassesTheContrastAudit() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [DemoLaunchArgument.resetThread]
        app.launch()
        let field = app.textFields[Ids.field]
        // Empty at launch, since no draft outlives one, so the placeholder shows.
        XCTAssertTrue(field.waitForExistence(timeout: uiTimeout), "The composer came up.")
        let composer = [field.frame, app.buttons[Ids.send].frame, app.buttons[DemoAccessibility.surprise].frame]
            .reduce(CGRect.null) { $0.union($1) }

        try app.performAccessibilityAudit(for: .contrast) { issue in
            // Everything off the composer is the audit above's to judge.
            guard let element = issue.element else { return false }
            return !composer.intersects(element.frame)
        }
    }

    /// Two follow-up chips at most, as the guide asks for.
    @MainActor
    func testFollowUpsAreCappedAtTwo() throws {
        let app = try launch()
        let starters = element(Ids.starters, in: app)
        XCTAssertTrue(starters.waitForExistence(timeout: uiTimeout))
        starters.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element(Ids.answer, in: app).waitForExistence(timeout: turnTimeout))

        // The one assertion here that stays conditional, and for a reason worth
        // writing down: follow-ups need a KEPT conversation to be answered
        // against, so `AskConversationStore.followUps` is empty unless the
        // engine keeps one (`hasKeptConversation`). A scripted answer returns
        // before any session exists, so scripting this turn would suppress the
        // very chips it was meant to force. Whether a real turn offers any is the model's
        // choice; what is pinned is the cap, which is the rule.
        let followUps = element(Ids.followUps, in: app)
        try XCTSkipUnless(followUps.waitForExistence(timeout: uiTimeout),
                          "This turn offered none — see the note above on why this cannot be scripted.")
        // "Another pick" leads the same bank under a pick, and it is not a
        // follow-up the model wrote.
        let written = followUps.buttons.matching(NSPredicate(format: "identifier != %@", Ids.anotherPick))
        XCTAssertLessThanOrEqual(written.count, 2)
    }

    /// The answer's prose reaches no menu of its own — which is why "Copy
    /// answer" hangs off the question bubble.
    ///
    /// `AskAnswerProse` asks for `.textSelection(.enabled)`, and on iOS 27 that
    /// is system selection rather than a callout menu. The obvious reading is
    /// that a long press on an answer hands the reader the system's own Copy,
    /// which would make that menu item a duplicate and the "menu lives on the
    /// question and nowhere else" rule worth reopening.
    ///
    /// Driven, it does not: pressed as one element and pressed again on its
    /// widest line of prose, the answer brings up nothing at all, while the
    /// same press on the question bubble in the same run brings up Copy and
    /// Ask again. By then the prose is a plain `Text` with no renderer
    /// (`AskStreamingText`), and why the press selects nothing isn't known;
    /// only the outcome is.
    ///
    /// So "Copy answer" is the only way an answer's words leave the screen. If
    /// this test starts failing, selection has begun winning and both that item
    /// and the rule above are worth revisiting — which is the whole reason it
    /// asserts a negative.
    @MainActor
    func testTheAnswersProseReachesNoMenuOfItsOwn() throws {
        let app = launchScripted()
        let starters = element(Ids.starters, in: app)
        XCTAssertTrue(starters.waitForExistence(timeout: uiTimeout))
        starters.buttons.element(boundBy: 0).tap()
        let answer = element(Ids.answer, in: app)
        XCTAssertTrue(answer.waitForExistence(timeout: turnTimeout))

        // The control. Without it a press that landed nowhere at all would pass
        // the two negatives below and report the opposite of what happened.
        element(Ids.question, in: app).press(forDuration: 1.2)
        XCTAssertTrue(app.buttons[Ids.questionCopy].waitForExistence(timeout: uiTimeout),
                      "The question bubble's menu is this test's control.")
        tapTheNavigationBar(of: app)
        XCTAssertTrue(app.buttons[Ids.questionCopy].waitForNonExistence(timeout: uiTimeout))

        // **The negatives go by the label, on purpose.** What they rule out is
        // any Copy, the system's own from a selection included, and the
        // system's carries no identifier of AskKit's. They read English, the
        // language this suite runs in.

        // The answer as the reader meets it: one element.
        answer.press(forDuration: 1.2)
        XCTAssertFalse(app.buttons["Copy"].waitForExistence(timeout: 3),
                       "A long press on the answer reaches no menu.")
        tapTheNavigationBar(of: app)

        // And its prose directly, in case the one element was what swallowed
        // the press: the widest static text inside the answer's frame.
        let prose = app.staticTexts.allElementsBoundByIndex
            .filter { answer.frame.contains($0.frame.origin) && $0.frame.width > 100 }
            .max { $0.frame.width < $1.frame.width }
        let line = try XCTUnwrap(prose, "The answer draws a line of prose to press.")
        line.press(forDuration: 1.2)
        XCTAssertFalse(app.buttons["Copy"].waitForExistence(timeout: 3),
                       "Nor does a long press on the prose itself.")
    }

    /// A tap that does nothing but put away what a long press brought up: in
    /// the middle of the navigation bar, where a phone has its title, at a
    /// point taken from the window.
    ///
    /// Not `app.tap()`: on iPhone Duo's inner display on its side the
    /// application's frame reads upright, 669 × 951, in a window 951 × 669,
    /// and a tap at its middle left the question's menu up.
    @MainActor
    private func tapTheNavigationBar(of app: XCUIApplication) {
        let window = app.windows.firstMatch
        let bar = app.navigationBars.firstMatch.frame
        window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: bar.midX - window.frame.minX, dy: bar.midY - window.frame.minY))
            .tap()
    }
}
