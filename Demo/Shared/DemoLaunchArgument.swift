import Foundation

/// Launch arguments the demo honours, declared once and compiled into **both**
/// the app and the UI-test bundle.
///
/// The two are separate processes with no module between them, so a launch
/// argument is otherwise a string literal typed twice — and a typo in either
/// copy is silent: the app simply does not reset, and the test fails somewhere
/// else entirely. In the project, it's in the Compile Sources of the three app
/// targets and the UI-test target.
///
/// Each one but `holdTurn` and `assistant` is also in the Run arguments of
/// the three app schemes (`AskKitDemo_iOS`, `_macOS` and `_visionOS`), off, so
/// it can be ticked in Xcode's scheme editor; those two are passed at launch,
/// or added to a scheme by hand. A new one goes into all three, added there
/// in Xcode.
nonisolated enum DemoLaunchArgument {
    /// Start with an empty thread: `AskPersistence.perLaunch` instead of
    /// `.thread`, so nothing is restored and nothing is saved.
    ///
    /// A persisted thread and a UI-test suite do not mix — "the first screen
    /// shows three chips" passes alone and fails after any test that left a
    /// turn on disk.
    static let resetThread = "-askResetThread"

    /// Keep chats (`.thread`), but start with none: the chat on disk, every
    /// earlier one, any thread set aside because it couldn't be read and the
    /// feedback attachments are deleted before the store reads them.
    ///
    /// For the history test, which needs a domain that keeps its chats and a
    /// list holding only what the test filed itself. Read in Debug builds
    /// only, which the UI tests run: it deletes the app's own chats.
    static let freshHistory = "-askFreshHistory"

    /// Answer every question with a fixed answer that has tiles, without
    /// asking a model.
    ///
    /// Tiles are the model's choice, so on a real turn a test of what a tile
    /// does can only skip when the model chooses none, and report green
    /// having checked nothing. So the tests that tap a tile
    /// (`AskItemOpenAction`) take the model out of the question instead.
    ///
    /// Not follow-ups: those need a kept conversation, which a deterministic
    /// answer never creates.
    ///
    /// No model is needed at all: without Apple Intelligence the first screen
    /// keeps its starters and a live composer (`DemoDomain.firstScreenPolicy`).
    static let scriptedAnswer = "-askScriptedAnswer"

    /// Hold every turn in flight until Stop: the demo answers every question
    /// itself, as under `scriptedAnswer`, and its answer never comes, so the
    /// wait row stays up and the spectrum's glass rod keeps drifting. The
    /// turn's deadline is ten minutes rather than 45 s.
    ///
    /// For what only shows while a turn is in flight: screenshots of the wait
    /// row and the rod's drift, and a profile of what the screen costs while
    /// it waits, which a real turn ends before a 10 s trace does.
    ///
    /// Not in the schemes' Run arguments: pass it at launch, as
    /// `xcrun simctl launch <device> com.example.askkitdemo -askHoldTurn`.
    static let holdTurn = "-askHoldTurn"

    /// Open an Ask link at launch: the argument after this flag is
    /// `askkitdemo://ask?q=…` (`DemoLink.askLink(question:)`). It goes through
    /// the router a link the system opens goes through, so a UI test covers
    /// `AskLink` as well as `AskConversationStore.prefill(_:)` — and, like
    /// every entry point, it never sends.
    ///
    /// **A link, not the question.** XCUITest hands launch arguments over
    /// through a shell-style split: "What's the oldest thing I have?" arrives
    /// as `Whats\ the\ oldest\ thing\ I\ have?`, its apostrophe eaten and every
    /// space escaped. A link encoded down to letters and digits leaves the
    /// split nothing to mangle.
    static let prefill = "-askPrefill"

    /// The composer's accessory button is the photo button instead of the
    /// demo's Surprise me, since a composer has one accessory button, and the
    /// photo it attaches is one the demo draws.
    static let photos = "-askPhotos"

    /// Host the screen in a tab, the way a host usually does on iPhone and iPad:
    /// a `TabView` of two, Ask first. At regular width on an iPad the tab bar
    /// sits at the top of the window, in the navigation bar's row, which is a
    /// bar the screen has to share. iOS only; elsewhere the flag does nothing.
    static let tabs = "-askTabs"

    /// With `tabs`, rest the composer in the tab bar's slot
    /// (`askComposerSlot`): its face rides beside the bar when the bar
    /// minimizes, and a tap raises the composer over the keyboard. The Library
    /// tab puts a host's own accessory in the slot (`DemoGlance`). Without
    /// `tabs` there is no tab bar and no slot, and the flag does nothing.
    static let slot = "-askSlot"

    /// A tile pushes the row it names onto the Ask tab's stack, as a host on
    /// the phone pushes its own, instead of showing it in a sheet. A sheet
    /// leaves the thread on screen under it; a push takes the thread off
    /// screen, and with it the face out of the slot (`AskComposerSlotCover`).
    static let push = "-askPush"

    /// Arrange the screen around a fold the simulator doesn't have: the
    /// argument after this flag is `book`, `bookBent`, `upright` or
    /// `uprightBent` (`AskSimulatedFold`). iPhone Duo's two panes, or the
    /// first screen's halves, on an iPhone or an iPad.
    ///
    /// The arrangement alone: no bar strip, and not the Duo's sizes. The Duo
    /// simulator shows the rest, in the poses someone can set on it.
    static let fold = "-askFold"

    /// Own nothing: the demo's overview reads as empty, so the first screen
    /// is the nothing-to-ask one, a mark and a sentence. With `button` as the
    /// argument after this flag the screen has its button too, which a host
    /// gives it for adding a first item.
    ///
    /// The demo has nothing to add, so its button shows the Library tab
    /// where there is one (`tabs`) and does nothing else. Only the overview
    /// is empty, which is all the first screen reads: a question typed
    /// anyway still searches the thirty rows.
    ///
    /// Where no model can serve, the first screen says that instead: the
    /// reason outranks an empty library (`AskStage`).
    static let emptyLibrary = "-askEmptyLibrary"

    /// Host the assistant (`DemoAssistantDomain`) in place of the library: a
    /// domain without rows, which converts units with one tool, proposes
    /// reminders with another, and answers from the model alone when neither
    /// applies. Its answers carry no tiles, and the line under each says what
    /// it stood on: the assistant's own words where a tool grounded it, and
    /// AskKit's "Not from this app's data" where nothing did.
    ///
    /// Only one Ask is built, the one this picks, since a process has one
    /// model seam. `resetThread`, `freshHistory`, `scriptedAnswer`, `prefill`
    /// and `fold` work with it as they do with the library; `photos`, `tabs`,
    /// `slot`, `push` and `emptyLibrary`, which are about the library's
    /// screen, do nothing.
    static let assistant = "-askAssistant"

    /// On the Mac, in a Debug build: write the window to a PNG at the path
    /// after this flag, then quit (`DemoWindowCapture`). How the README's Mac
    /// images are made. A script launches the demo as its own child and hands
    /// it the file as `/dev/fd/4`, which a sandboxed app can write where it
    /// can write no path outside its container.
    static let captureWindow = "-askCaptureWindow"

    /// With `captureWindow`: the seconds to wait once the window is up before
    /// writing it, the argument after this flag. Eight without one.
    static let captureAfter = "-askCaptureAfter"

    /// With `captureWindow`: the window's content size, the argument after
    /// this flag, as `1280x800`, which is the size without one.
    static let captureSize = "-askCaptureSize"

    /// The argument after `flag`, when there is one.
    static func value(after flag: String, in arguments: [String] = CommandLine.arguments) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}

/// The demo's URL scheme: `askkitdemo://ask?q=…` opens with the question in the
/// composer, through `AskLink`. Declared in `AskKitDemo/Info.plist` as well.
nonisolated enum DemoLink {
    static let scheme = "askkitdemo"

    /// `askkitdemo://ask?q=…`, with everything but letters and digits
    /// percent-encoded. The UI-test bundle does not import AskCore, so this is
    /// `AskLink.url` spelled out — and stricter, for the launch-argument split
    /// `DemoLaunchArgument.prefill` describes.
    static func askLink(question: String) -> String {
        let encoded = question.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        return "\(scheme)://ask?q=\(encoded)"
    }
}

/// Words the demo's assistant writes that the UI test reads back, declared
/// once for the reason `DemoLaunchArgument` is.
nonisolated enum DemoAssistantWords {
    /// The evidence line under an answer one of the assistant's tools
    /// grounded (`DemoAssistantDomain.evidence(for:)`).
    static let fromItsTools = "From this app's tools"
}

/// Identifiers the demo's own views carry — the ones outside `AskAccessibility`,
/// which is AskUI's namespace and not the host's to add to.
nonisolated enum DemoAccessibility {
    static let rowDetailTitle = "demo.rowDetail.title"
    /// The composer's accessory button the demo hands `AskScreen`, Surprise me.
    static let surprise = "demo.surprise"
    /// The card the demo draws from a turn's payload.
    static let spanCard = "demo.spanCard"
    /// The host's own accessory the demo puts in the slot on its Library tab.
    static let glance = "demo.glance"
    /// The assistant's toolbar button that lists the reminders added.
    static let reminders = "demo.reminders"
    /// One reminder in that list.
    static let reminder = "demo.reminder"
}
