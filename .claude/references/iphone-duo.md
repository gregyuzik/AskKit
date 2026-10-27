# iPhone Duo

For changing AskUI's iPhone Duo behaviour and testing it. The layout rule (size class and measured size,
never idiom or orientation) and what the 27.2 floor means for the bars are in [AGENTS.md](../../AGENTS.md);
the arrangements are in [docs/ARCHITECTURE.md](../../docs/ARCHITECTURE.md#platforms-and-sizes).

## Changing the fold code

Why the fold is arranged as it is, with the measurements, is in ARCHITECTURE.md and the doc comments of
`AskFold`, `AskFoldPanes`, `AskFoldArrangement`, `AskFoldSplit` and `AskFirstScreen.onKeyboard`. Also:

- After any change to `AskFoldPanes`, check that the demo idles: with the chats pane up at 180° it sits at
  0 to 3.5% CPU (`top -pid`). A fold read in the panes' own space can loop, and then the first screen is
  never drawn.
- A `NavigationStack` sets aside the strip's 84 pt on the hardware side of its own bounds wherever it
  stands, so a stack in the pane away from the strip loses that width, and
  `.toolbarVerticalBehavior(.disabled)` on its root changes nothing. The chats pane is a `List` with its
  own header and isn't affected.

## Testing on a Duo simulator

- **The simulator** is device type `com.apple.CoreSimulator.SimDeviceType.iPhone-Duo` on runtime
  `com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4`. `scripts/duo.sh` (its header lists every
  command) drives the demo on the one booted Duo, or the one `ASKKIT_DUO_UDID` names, and writes under
  `tmp/duo/`, which git ignores.
- **Set the pose first**, in Device Hub, and never quit it: that shuts down every simulator. Neither the
  script nor a UI test opens, closes or turns the Duo; `scripts/duo.sh orient` shows what the displays
  made of the pose. The outer display's home screen stays upright whatever is sent, so judge a closed
  pose with the demo in front.
- **Reach.** While the Duo is open, `simctl` taps and keys reach only the outer display. Its screenshots
  and recordings reach both (`--display=1` outer, `--display=3` inner), and XCUITest reaches the inner
  one: walk an open pose by launch argument for stills and by UI test for touch.
- **Sizes.** Closed, the outer display is 466 × 678 upright and 678 × 466 on its side (Landscape Right,
  the strip on the left). Open, the inner display is 669 × 951 upright, with the bars along the top. On
  its side the window is 951 × 669, the strip takes its last 84 pt, leaving 867, and the fold is at
  x 455.5 to 495.5; upright it is at y 455.5 to 495.5 of the display.
- **Without a Duo**, `-askFold` ([README.md](../../README.md#the-demo)'s launch-argument table) shows the
  arrangement alone, and no scene moves between displays under it: say so wherever a capture of it is
  used, and leave it off on the Duo. Two panes need 240 pt for the chats and 320 for the conversation, so
  an iPhone 18 Pro shows them only on its side, and an iPad mini either way.
- **The other first screens** want `-askFreshHistory`, which deletes what AskKit keeps for the demo:
  `duo.sh open <pose> both` copies it out and back, and for a launch of your own, copy
  `Library/Application Support/AskKitDemo` out of the demo's data container (`xcrun simctl
  get_app_container <UDID> com.example.askkitdemo data`, asked for each time) and back after.
  `-AppleLanguages "(he)" -askScriptedAnswer` is can't-serve with its starters, and without
  `-askScriptedAnswer` with none: the simulator's model doesn't write Hebrew.
- **UI tests** (`AskKitDemoUITests`) tell the Duo by `SIMULATOR_MODEL_IDENTIFIER` (`iPhone19,4`; the
  iPhone 18 Pro is `iPhone19,2`), and a test whose assumption fails there skips and says which. Open
  flat, the side strip doesn't minimize on the reader's scroll down, so the tests of the bars minimizing
  skip. On the inner display on its side the application's frame reads 669 × 951 where its window's is
  951 × 669: take coordinates from `app.windows.firstMatch`. XCUITest lists elements hidden from
  accessibility, such as the resting composer's whole row, so assert reach by touch and by frame, not
  `isHittable`. Closed on its side, taps land only while the outer display is drawing.
- **No software keyboard?** `xcrun simctl spawn <UDID> defaults write com.apple.keyboard.preferences
  AutomaticMinimizationEnabled -bool false`, then relaunch.

## Open

Work an outsider could pick up. The comments named hold what is known.

- **Split View on the Duo has never been seen**: whether a half is compact width, whether a fold is
  reported there, and which edge the strip takes. It is a drag of the home indicator in Device Hub.
- **At launch the line between the panes moves once**, as the system's split does: the view's middle
  (433.5 of 867) is 42 pt short of the fold's. Placing it at the window's middle would leave nothing to
  move, and is left undone: that guesses the Duo's geometry, where the system's split guesses none.
- **The keyboard's hide starts on a 28 pt step** in a tabletop: the nothing-to-ask button is at 296 in the
  first frame and at 284 five frames later. Not traced. The leads: 28 is half the 54 pt the composer gives
  back as it comes to rest, and UIKit's clock for the scroll view meets SwiftUI's for the column in that
  frame (`AskKeyboard.change(_:to:duration:curve:in:)`). Why the show glides is unknown (`onKeyboard`).
- **A reopened chat that stands at its top.** A saved one-turn chat opened after a relaunch, on its side
  and flat, showed its follow-up suggestion under the composer until scrolled. The guess, untraced: the
  chat fit when the thread's scroll task ran (`AskScreen.thread`, `follow.isScrollable`) and the
  suggestion landed after. Not reproduced in the demo; it wants a reopen that overflows by less than a
  suggestion's height.
- **Not looked at on the Duo:** the composer at the largest text size (`AskComposerMetrics`),
  nothing-to-ask beside the fold with the keyboard up, and two windows side by side (seen on an iPad).
  A drop target for the composer is not started: it is public API.
