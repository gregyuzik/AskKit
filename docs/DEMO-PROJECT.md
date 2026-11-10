# The demo

`Demo/` is an app for iOS, macOS and visionOS that hosts two domains, each with a thread and chats of
its own. "Your Things" (`DemoDomain`) is a library of thirty things, books, records, tools and clothes,
behind one search tool. "Assistant" (`DemoAssistantDomain`) has no rows: it converts units with one tool,
proposes reminders with another, and answers anything else from the model alone. The switch between them
is a menu on iOS and iPadOS, the last of the bar's leading items; the title's menu on visionOS; and on the
Mac a pop-up in the toolbar and the View menu (⌘1 and ⌘2). The demo opens where it was left, on the
library the first time. Both domains share one model seam, as a host's Asks would, and each keeps its
turn going while the other is on screen. The demo declares no Private Cloud Compute entitlement, so it
always answers on the device.

Its Ask tab wears `askkit.bubbles`, a custom symbol in its asset catalog, and its mark the symbol's
`askkit.bubbles.fill` sibling: three speech bubbles of one size, each up and to the right of the one in
front. `scripts/make-demo-symbol.swift` draws it. Its icon is the same three bubbles as plates of Liquid
Glass, shading through `AskSpectrum.aurora`'s colors. `scripts/make-demo-icon.py` makes it from the
symbol's drawing, so the icon and the tab can't drift apart.

## Running it

Open `Demo/AskKitDemo.xcodeproj` and run `AskKitDemo_iOS` on an iPhone 18 Pro simulator, or
`AskKitDemo_macOS` or `AskKitDemo_visionOS`. The simulator and the Mac need no signing. A real turn needs
Apple Intelligence, and `-askScriptedAnswer` needs no model. To run on a device, put
`DEVELOPMENT_TEAM = <your team ID>` in an untracked `Demo/Local.xcconfig`.

Every launch argument is declared in `Demo/Shared/DemoLaunchArgument.swift`. All but `-askAssistant`,
`-askHoldTurn` and `-askHidesTips` are listed, off, in each app scheme's Run > Arguments: tick one to use
it. Add those three to the scheme in Xcode, or pass one at launch, as
`xcrun simctl launch <device> com.example.askkitdemo -askAssistant`. The three that image the Mac window
are under [Imaging the Mac window](#imaging-the-mac-window).

| Argument | What it shows |
|---|---|
| none | The domain the demo was left on, the library the first time. On the library, a real turn on the on-device model, starters drawn from the thirty items, "Surprise me" before the composer, and a gear button for the settings card. |
| `-askResetThread` | An empty thread on every launch (`.perLaunch`), in both domains: nothing is restored or saved. It opens on the library, or the assistant under `-askAssistant`, whatever was on screen last, and a switch isn't remembered. |
| `-askFreshHistory` | The thread kept, but everything AskKit keeps for the demo deleted before the store reads it, in both domains: the saved thread, every earlier chat, any thread set aside as unreadable, and the feedback attachments, for a clean History sheet. The remembered domain goes too, so it opens on the library, or the assistant under `-askAssistant`. |
| `-askScriptedAnswer` | The app answers every question, with no model. "What should I read tonight?" gets a pick with a basis line and Another pick, a question with "lend" in it a confirmation card, and anything else a two-tile lookup. The first screen keeps its starters even where Apple Intelligence is off. |
| `-askPrefill <link>` | An Ask link opened once at launch, such as `askkitdemo://ask?q=…`: the question lands in the composer with the keyboard up, unsent. Reopening a window, returning to a tab or switching domains doesn't open it again. |
| `-askPhotos` | The photo button in place of "Surprise me". It attaches a record sleeve the demo draws, and the answer notes that it read only the words. |
| `-askTabs` (iOS) | The screen in a `TabView` of two tabs, Ask and Library. |
| `-askSlot` (iOS, with `-askTabs`) | The composer's face in the tab bar's bottom accessory. The Library tab puts a host's own accessory there. |
| `-askPush` | A tile pushes its row onto the Ask tab's stack instead of showing it in a sheet. |
| `-askFold <shape>` | The screen arranged around a fold the simulator doesn't have: `book`, `bookBent`, `upright` or `uprightBent`. |
| `-askEmptyLibrary` | An empty library, so the first screen is the nothing-to-ask one; `-askEmptyLibrary button` adds its button. |
| `-askHoldTurn` | Every turn held in flight until Stop, answered as under `-askScriptedAnswer` with an answer that never comes: the wait row stays up, for screenshots and profiles of a turn in flight. |
| `-askHidesTips` | AskUI's tips hidden, as every UI test launches the demo. Without it the demo configures TipKit at launch and shows them; TipKit remembers a tip that has gone, so delete the app to see them again. |
| `-askAssistant` | Opens on the assistant, whatever was on screen last; the switch still goes back to the library. The assistant shows no tiles, and under each answer the line saying what it stood on: its own words where a tool grounded it, "Not from this app's data" where nothing did. A reminder waits for the reader's tap on its card and lasts for the launch, listed in a Reminders section of the settings card. With `-askScriptedAnswer`, a question with "remind" in it gets the card, one with "miles" a conversion, and anything else an answer nothing grounded. `-askResetThread`, `-askFreshHistory`, `-askPrefill` and `-askFold` work with it; the library's other arguments do nothing there. |

`-AppleLanguages (he)` runs the demo in Hebrew, right to left; add `-askScriptedAnswer` where no model on
the device writes Hebrew.

## The project

`Demo/AskKitDemo.xcodeproj/project.xcproj` is the demo's project, in Xcode 27.2's JSON format (JSON5,
which Xcode writes in one canonical form and which keeps no comments). It is committed with the four
shared schemes (`xcshareddata/xcschemes/`), `project.xcworkspace/contents.xcworkspacedata` and
`project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings`; `xcuserdata/` is ignored.
`Demo/AskKitDemo/Info.plist`, the app targets' entitlements files beside it and
`Demo/Signing.xcconfig` are tracked, and are the source of their keys: nothing regenerates them.

## Editing it

- **In Xcode**, with `xcrun xcodeproj` (`target`, `setting`, `group`, `pkg` and `config`, each taking
  `-P Demo/AskKitDemo.xcodeproj`), or in `Demo/Signing.xcconfig`. Edit the schemes in Xcode.
- **A hand edit to the JSON** has to pass `scripts/ci.sh checks`, which fails a `project.pbxproj`
  beside it (Xcode refuses a bundle holding both: "has multiple project definition files, and is
  invalid"), a file `xcrun xcprojformatter` would rewrite (a typo'd or duplicate key, or a comment,
  which Xcode's next save would drop), and a project `xcrun xcodeproj target list` can't load (a
  dangling reference). The check prints the formatter's diff. Lines may move, but a removed line is a
  key the formatter would drop: a typo, or a merge that kept both sides of a conflict, whose duplicate
  key `xcrun xcprojformatter --update` resolves by silently losing one side. Fix that by hand, then run
  `xcrun xcprojformatter --update Demo/AskKitDemo.xcodeproj`.
- **A new file needs only to be on disk.** `AskKitDemo/`, `Shared/` and `AskKitDemoUITests/` are
  synchronized folders, so a file in one joins its folder's targets, in the build phase its type picks:
  the three app targets for `AskKitDemo/`, those and `AskKitDemoUITests` for `Shared/`, and the UI-test
  target alone for `AskKitDemoUITests/`. `AskKitDemo/Info.plist` is excluded from the app targets,
  being their `INFOPLIST_FILE`. The entitlements files there need no exclusion: no build phase takes
  one, so none is copied into an app. A file that must stay out of a target takes
  `xcrun xcodeproj group exclude <name> --group /<folder> --target <target>`, once per target; one in a
  subfolder is a hand edit of the folder's `membership-exceptions` (`"Sub/File.swift"`).
  `Signing.xcconfig` sits outside every folder, in the plain "Configuration" group, because
  `xcrun xcodeproj config set` refuses an xcconfig inside a synchronized folder.

## Why the settings are what they are

- **Signing** is `Demo/Signing.xcconfig`'s, which both configurations are based on: none on a
  simulator or the Mac, and on a device the team a developer puts in an untracked `Demo/Local.xcconfig`
  (the xcconfig says how, and why the bundle ID takes the team as a suffix). Nothing in the project
  sets `CODE_SIGNING_ALLOWED` or `DEVELOPMENT_TEAM`: a project or target setting outranks the
  xcconfig, so it would override device signing and the developer's team.
- **What a shipping host turns on, and the demo leaves off:** the Mac app runs unsigned, so its App
  Sandbox, hardened runtime and Enhanced Security entitlements take effect only once `Local.xcconfig`
  signs it; and warnings aren't errors.
- **`EXCLUDED_ARCHS = x86_64`**, for the whole project: arm64 only. Every deployment target is 27.2, and
  no Intel Mac runs macOS 27, so the x86_64 half of a macOS or simulator build would be compiled and
  thrown away. Subtracting the one dead arch, rather than pinning `ARCHS = arm64`, stays right if
  `ARCHS_STANDARD` changes.
- **`SWIFT_TREAT_WARNINGS_AS_ERRORS = NO`.** The push gate and CI fail on every warning in the demo's
  sources and AskKit's anyway, and someone trying the demo under a newer Xcode can still run it past a
  new deprecation. A host without such a gate turns it on, for Release at least.
- **Enhanced Security is on**, in each app target, in both its halves. `ENABLE_ENHANCED_SECURITY = YES`
  adds pointer authentication, an arm64e slice beside arm64 on a device and the Mac; a simulator has
  no arm64e and builds arm64 alone. A Debug run on My Mac builds the arm64e slice alone, and a generic
  destination, the push gate's `generic/platform=macOS`, builds both. The runtime half is the
  `com.apple.security.hardened-process` entitlements: the main key, `enhanced-security-version-string`
  and `platform-restrictions-string` at `"2"`, `hardened-heap` and `dyld-ro`, in
  `AskKitDemo/AskKitDemo_<platform>.entitlements` (`CODE_SIGN_ENTITLEMENTS`), a file per target so
  that Xcode's Signing & Capabilities changes one target at a time. They are live only in a signed
  build; the unsigned Mac app carries none and runs its arm64e slice without them.
- **`WorkspaceSettings.xcsettings`** sets the three keys that build the package arm64e, which
  [ADOPTING.md's Enhanced Security](ADOPTING.md#enhanced-security) names for a host that turns it on.
  Without them a Mac build stops at "Unable to resolve module dependency: 'AskCore'", and a device build
  can't link AskCore and AskUI ("Undefined symbols for architecture arm64e").
- **One target per platform**, `AskKitDemo_iOS`, `AskKitDemo_macOS` and `AskKitDemo_visionOS`, with a
  scheme apiece, each compiling `AskKitDemo/` and `Shared/` and linking AskCore and AskUI from the
  package at `..`. `AskKitDemo_macOS` is a plain window, not Catalyst, so it declares its own category
  (`INFOPLIST_KEY_LSApplicationCategoryType`), and it asks for the App Sandbox and the hardened runtime
  (`ENABLE_APP_SANDBOX`, `ENABLE_HARDENED_RUNTIME`), as a shipping Mac app does. Signed, it carries
  those settings' entitlements and its entitlements file's together, and runs in its container, where
  everything AskKit and the demo write already lives: Application Support.
- **`INFOPLIST_FILE = AskKitDemo/Info.plist`** is a base plist that `GENERATE_INFOPLIST_FILE`'s keys
  are combined with. It carries the locale list and the URL scheme, and its comments say why. The
  project's localizations are `Base` and the same 24 locales, as the maintainers' catalog checker asks
  of every project; with no catalog of its own, the demo runs in them by the plist's list.
- **`INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad`** lists all four orientations, upside
  down included, on `AskKitDemo_iOS`. An iPad app that takes part in multitasking has to support
  every one, and without them a device build warns "All interface orientations must be supported
  unless the app requires full screen". The demo doesn't set `UIRequiresFullScreen` to quiet it:
  AskKit lays out by size class and measured size, so the app stays resizable, as a host's should.
  The iPhone's list is left unset: the check is the iPad's.
- **The launch arguments** are in each app scheme's Run arguments, off, so the scheme launches the demo
  plainly ([Running it](#running-it)). A flag for one platform alone, such as `-askTabs` or
  `-askCaptureWindow`, is listed in every scheme all the same. Three aren't: `-askAssistant`, which
  opens on the assistant rather than where the demo was left (the app's own switch moves between the
  domains and remembers which was on screen); `-askHoldTurn`, which holds every turn in flight; and
  `-askHidesTips`, which hides AskUI's tips for the UI tests.
- **`AskKitDemoUITests`** is iOS only. The smoke suite drives the screen on an iPhone 18 Pro simulator,
  and the Mac and visionOS apps are checked by hand, since a UI-test bundle per platform would be three
  flaky suites asserting one set of identifiers. It compiles `Shared/` too, so a launch argument isn't
  written twice, and links AskUI so the suite uses `AskAccessibility`: a renamed identifier breaks the
  build, rather than leaving the tests green against strings nothing sets.
- **The `AskKitDemoUITests` scheme** is its own, so the three app schemes stay what the push gate
  builds. The gate builds it and doesn't run it (`scripts/ci.sh ui-smoke` runs it). Its one build
  entry, the bundle, is built for Run as well as Test, so a plain `xcodebuild build` on the scheme has
  something to build: with Test alone, xcodebuild refuses the destination ("Supported platforms for
  the buildables in the current scheme is empty"). The app isn't in the scheme: the bundle depends on
  it, so building the scheme builds the app anyway.

## Imaging the Mac window

A Debug build of `AskKitDemo_macOS` can write its own window to a PNG, as it is composited, title bar,
glass and the system's window shadow included, then quit. The PNG is larger than the window by the
shadow's reach on every side, and transparent beyond the shadow and the window's corners. To make one,
tick `-askCaptureWindow` in the scheme's Run arguments and run: the PNG lands at
`$(BUILT_PRODUCTS_DIR)/AskKitDemo-window.png`. The Mac has to be unlocked and awake: with the login
window in front the window draws as inactive, and the capture logs which app kept the front.

| Argument | What it does |
|---|---|
| `-askCaptureWindow <path>` | Writes the window to `<path>`. A build signed through `Local.xcconfig` runs in the App Sandbox and can write no path outside its container, so launch its binary with the file as a descriptor: `AskKitDemo.app/Contents/MacOS/AskKitDemo -askCaptureWindow /dev/fd/4 4>window.png`. |
| `-askCaptureAfter <seconds>` | How long the window settles before it is written: 8 seconds by default. |
| `-askCaptureSize <W>x<H>` | The window's content size: 1280x800 by default. The PNG is at the display's scale. |

The README's `docs/images/mac.png` and `mac-dark.png` are the library in a 1100x900 window: two live
turns from the on-device model, "What records do I own?" and then "Which one is the oldest?". Both are
asked in one launch, since a second launch would start a fresh session with a recap, which the thread
marks with an "Earlier in this chat is summarized" line. A later launch reads the thread back and
images it. Each `-key value` pair goes before any bare flag, since AppKit pairs a `-`-prefixed argument
with the next one.

1. Launch with every chat forgotten, the first question in the composer, and a capture delay long
   enough to keep the app up. `caffeinate` execs the app in place, so `$!` is the app's pid:

   ```sh
   caffeinate -dimsu AskKitDemo.app/Contents/MacOS/AskKitDemo \
     -NSRequiresAquaSystemAppearance YES -AppleAccentColor 4 \
     -askCaptureWindow /dev/fd/4 -askCaptureAfter 150 -askCaptureSize 1100x900 \
     -askPrefill 'askkitdemo://ask?q=What%20records%20do%20I%20own%3F' \
     -askHidesTips -askFreshHistory 4>/dev/null &
   ```

2. Two or three seconds in, bring the window to the front with `open AskKitDemo.app`. The app asks for
   the front itself, but activation is cooperative and the terminal keeps it, so the window would draw
   as inactive. Run `open` only while the app is up: once it has quit, `open` starts another copy, with
   no arguments.
3. Send it. A Return posted to the window doesn't reach the composer's `onKeyPress`, and the Send menu
   item reports itself disabled, so post a click on the send button, at (860, 24) in a 1100-point-wide
   window (points, from the bottom left). Run these from a file, `xcrun lldb -p <pid> --batch -s <file>`,
   ending in `detach`. lldb's parser refuses an `NSPoint` argument, so the event is made through
   `objc_msgSend` with the point as two doubles, one expression a line (`$0` to `$2` are lldb's results):

   ```
   expr -l objc -- (long)[(NSWindow *)[(NSApplication *)[NSApplication sharedApplication] keyWindow] windowNumber]
   expr -l objc -- (id)((id (*)(id, SEL, NSUInteger, double, double, NSUInteger, double, NSInteger, id, NSInteger, NSInteger, float))objc_msgSend)((id)[NSEvent class], @selector(mouseEventWithType:location:modifierFlags:timestamp:windowNumber:context:eventNumber:clickCount:pressure:), (NSUInteger)1, (double)860, (double)24, (NSUInteger)0, (double)[(NSProcessInfo *)[NSProcessInfo processInfo] systemUptime], (NSInteger)$0, (id)nil, (NSInteger)0, (NSInteger)1, (float)1.0)
   expr -l objc -- (id)((id (*)(id, SEL, NSUInteger, double, double, NSUInteger, double, NSInteger, id, NSInteger, NSInteger, float))objc_msgSend)((id)[NSEvent class], @selector(mouseEventWithType:location:modifierFlags:timestamp:windowNumber:context:eventNumber:clickCount:pressure:), (NSUInteger)2, (double)860, (double)24, (NSUInteger)0, (double)[(NSProcessInfo *)[NSProcessInfo processInfo] systemUptime], (NSInteger)$0, (id)nil, (NSInteger)0, (NSInteger)1, (float)0.0)
   expr -l objc -- (void)[(id)[NSApplication sharedApplication] postEvent:(id)$1 atStart:(BOOL)NO]
   expr -l objc -- (void)[(id)[NSApplication sharedApplication] postEvent:(id)$2 atStart:(BOOL)NO]
   ```

4. Wait for the answer. The unsigned build keeps its thread at
   `~/Library/Application Support/AskKitDemo/ask-thread.json`, and a turn is there once it ends. Then
   type the second question into the composer and send it with the click above, in a second attach:

   ```
   expr -l objc -- (void)[(id)[(NSWindow *)[(NSApplication *)[NSApplication sharedApplication] keyWindow] firstResponder] insertText:(id)@"Which one is the oldest?"]
   ```

   Once that answer is saved, quit: `expr -l objc -- (void)[(id)[NSApplication sharedApplication] terminate:nil]`.
   Ask again from step 1 if either answer is padded.
5. Image it: launch again without `-askFreshHistory` or `-askPrefill`, with
   `-askCaptureAfter 8.5 4>mac-light.png`, and bring the window to the front. For dark, swap
   `-NSRequiresAquaSystemAppearance YES` for `-AppleInterfaceStyle Dark` (tried on a Mac set to dark)
   and write `mac-dark.png`. The composer's caret blinks, so retake with a slightly different delay
   (8.3 worked) until it doesn't show. On a 2x display an active window comes out 2424x2024; an
   inactive one is smaller, its shadow shorter. Convert each to sRGB and scale it to 1400 wide:

   ```sh
   sips --matchTo '/System/Library/ColorSync/Profiles/sRGB Profile.icc' --resampleWidth 1400 mac-light.png --out mac.png
   ```

6. Forget the chat with one more launch under `-askFreshHistory -askResetThread`, given
   `-askCaptureWindow /dev/fd/4 -askCaptureAfter 2` and `4>/dev/null` so it quits. `-askCaptureSize`
   also changes the window frame the demo saves, so read it before step 1
   (`defaults read com.example.askkitdemo`) and give this launch the old size.
7. Recompress each image losslessly once it is in `docs/images/`, before committing it:
   `oxipng -o max --strip safe docs/images/<file>.png` (`brew install oxipng`). The images are most of
   the repository's history, which every SwiftPM client clones, so a retake should land as small as it
   can.

## Imaging the iPhone screen

The README's six iPhone images are an iPhone 18 Pro simulator (iOS 27.2), each shot in light
(`iphone-<shot>.png`) and dark (`iphone-<shot>-dark.png`): the screen alone, with no device around
it, its corners clear to the display's shape, scaled to 534x1163:
- `first`: the library's first screen, nothing asked;
- `answer`: a live answer from the on-device model to a starter, "What records do I own?" in light and
  "What books do I own?" in dark ("What tools do I own?" came back padded in every take);
- `card`: the assistant's live answer to its starter "Remind me to water the plants at 6 PM", the
  reminder's card not yet confirmed.

Live answers vary, so take a few and keep one whose prose names the items with no padding. Hold the
simulator for the whole run, so no test or other app comes to the front on it.

1. Build and install `AskKitDemo_iOS` (Debug) on the simulator, then set Apple's status bar and the
   appearance, `light` or `dark`:

   ```sh
   xcrun simctl ui <udid> appearance light
   xcrun simctl status_bar <udid> override --time 9:41 --dataNetwork wifi --wifiMode active \
     --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100
   ```

2. Launch on the library's first screen with the tips hidden, nothing saved and no domain
   remembered, adding `-askAssistant` for `card`:

   ```sh
   xcrun simctl launch --terminate-running-process <udid> com.example.askkitdemo \
     -askHidesTips -askFreshHistory -askResetThread
   ```

3. Ask by activating the starter, and wait for the answer, its tiles and the follow-ups (20 to 45
   seconds). A tap through Xcode's device interaction works. The repeatable way,
   and the only one on visionOS, is lldb (`xcrun lldb -p <pid> --batch -o '…' -o detach`). First turn
   on the app's accessibility, without which SwiftUI builds no accessibility elements:
   `expr -l objc -- ((void (*)(int))dlsym((void*)-2, "_AXSApplicationAccessibilitySetEnabled"))(1)`.
   Then walk the window's elements from `[[UIApplication sharedApplication] windows]`
   (`accessibilityElementCount`, `accessibilityElementAtIndex:`, and `subviews` where a view has no
   elements), find the one labelled with the starter, and send it `accessibilityActivate`.
4. Put the question just under the bar. An answer with eight tiles and two follow-ups runs a little
   taller than the screen, and the screen settles at the thread's foot with the question under the bar
   (the card's turn fits, and needs no scroll). Set
   the offset of the thread's scroll view (the `UIScrollView` with the identifier `ask.root`)
   directly: `expr -l objc -- (void)[(id)<scroll view> setContentOffset:(CGPoint){0, <y>} animated:NO]`,
   with `<y>` the current offset less the distance from the question's top to 4 pt under the bar's
   bottom (116 pt). That puts the turn's time under the bar, and the last follow-up runs under the
   composer's glass, as a chat's does. A drag on the thread is less precise, and one on the answer's
   words selects them.
5. Capture the screen and clear its corners. A plain capture is the whole 1206x2622 rectangle, with
   the pixels the display's corners hide. One taken with `--mask=alpha` has those corners clear, but
   paints the Dynamic Island as a black pill between the clock and the status icons. So take both,
   use ImageMagick (`brew install imagemagick`) to give the plain capture the masked one's alpha,
   which is opaque across the island, and scale the result to 534x1163:

   ```sh
   xcrun simctl io <udid> screenshot iphone-raw.png
   xcrun simctl io <udid> screenshot --mask=alpha iphone-mask.png
   magick iphone-raw.png \( iphone-mask.png -alpha extract \) -alpha off \
     -compose CopyOpacity -composite iphone-cut.png
   sips -z 1163 534 iphone-cut.png --out iphone-answer.png
   ```

6. Put the simulator back: `xcrun simctl status_bar <udid> clear`, its own appearance, the app's
   accessibility off (the same call with `0`), and the app quit.
7. Recompress each image as in step 7 of [Imaging the Mac window](#imaging-the-mac-window).

## Imaging the Apple Vision Pro window

The README's `docs/images/vision.png` is the demo's window on an Apple Vision Pro simulator (visionOS
27.2), cut out of the simulator's 3840x2160 capture with transparency around it, on a live answer to
the library's "What clothes do I own?". No input tool reaches a visionOS simulator, so the turn is
asked through lldb.

1. Build and install `AskKitDemo_visionOS`, and launch it as in step 2 above.
2. Turn on the app's accessibility and activate the "What clothes do I own?" starter as in step 3
   above. If the answer comes back "Answer cut short", launch again and ask again.
3. Make the window tall enough for the whole turn. In the default 1280x720 window the turn doesn't
   fit between the bar and the composer at any scroll offset: the turn's time sits under the bar or
   a follow-up lies over the composer. At 1280x860 it fits without scrolling:

   ```
   expr -l objc -- (void)[(id)[(id)<window> windowScene] requestGeometryUpdateWithPreferences:(id)[(id)[(Class)NSClassFromString(@"UIWindowSceneGeometryPreferencesVision") alloc] initWithSize:(CGSize){1280, 860}] errorHandler:nil]
   ```

   lldb reports the expression interrupted (`EXC_BREAKPOINT`), but the window takes the size: check
   the window's `bounds`. Set it back to 1280x720 afterwards, since visionOS can restore a window's
   size on the next launch.
4. Capture with `xcrun simctl io <udid> screenshot vision-raw.png`. The window is drawn at about
   1.371 px a point, centred across the capture. The title floats in a pill above the window, not in
   the window's bar: on visionOS the switch is the title's menu (`DemoDomainSwitch`), and visionOS
   draws a title with a menu as a pill with the app's icon and a chevron. Find
   both edges in the capture, where the window's glass meets the room. At 1280x860 the window ran
   from x 1042 to 2797 and y 592 to 1770, and the pill from x 1795 to 2046 and y 496 to 557.
5. Cut it out. Crop from the pill's top to the window's bottom. Make the alpha mask the window as a
   rounded rectangle, with a 60 px corner radius and inset 5 px to drop the glass's rim, where the room
   shows through, plus the pill as a capsule, and make everything else transparent.
6. In the README, the three iPhone images share a row at 30% each, and the Mac and Apple Vision Pro
   images a second row at one height: their `width=` percentages are in proportion to each image's
   width over its height, 45% and 52%.
7. Put the simulator back: the window at 1280x720, the app's accessibility off, and the app quit.
8. Recompress `vision.png` as in step 7 of [Imaging the Mac window](#imaging-the-mac-window).
