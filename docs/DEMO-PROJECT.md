# The demo's project

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
- **`WorkspaceSettings.xcsettings`** sets `iOSPackagesShouldBuildARM64e`,
  `macOSPackagesShouldBuildARM64e` and `visionOSPackagesShouldBuildARM64e`. A SwiftPM package doesn't
  follow the app to arm64e on its own: without them a Mac build stops at "Unable to resolve module
  dependency: 'AskCore'", and a device build can't link AskCore and AskUI ("Undefined symbols for
  architecture arm64e"). A host that turns Enhanced Security on needs the same keys, in its project's
  `project.xcworkspace/xcshareddata/` or its workspace's `xcshareddata/` (README's Install).
- **One target per platform**, `AskKitDemo_iOS`, `AskKitDemo_macOS` and `AskKitDemo_visionOS`, with a
  scheme apiece, each compiling `AskKitDemo/` and `Shared/` and linking AskCore and AskUI from the
  package at `..`. `AskKitDemo_macOS` is a plain window, not Catalyst, so it declares its own category
  (`INFOPLIST_KEY_LSApplicationCategoryType`), and it asks for the App Sandbox and the hardened runtime
  (`ENABLE_APP_SANDBOX`, `ENABLE_HARDENED_RUNTIME`), as a shipping Mac app does. Signed, it carries
  those settings' entitlements and its entitlements file's together, and runs in its container, where
  everything AskKit and the demo write already lives: Application Support.
- **`INFOPLIST_FILE = AskKitDemo/Info.plist`** is a base plist that `GENERATE_INFOPLIST_FILE`'s keys
  are combined with. It carries the locale list and the URL scheme, and its comments say why.
- **`INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad`** lists all four orientations, upside
  down included, on `AskKitDemo_iOS`. An iPad app that takes part in multitasking has to support
  every one, and without them a device build warns "All interface orientations must be supported
  unless the app requires full screen". The demo doesn't set `UIRequiresFullScreen` to quiet it:
  AskKit lays out by size class and measured size, so the app stays resizable, as a host's should.
  The iPhone's list is left unset: the check is the iPad's.
- **The launch arguments.** Every `DemoLaunchArgument` but `-askAssistant` and `-askHoldTurn` is in
  each app scheme's Run arguments, off, so the scheme launches the demo plainly; tick one to use it. A
  flag for one platform alone, such as `-askTabs` or `-askCaptureWindow`, is listed in every scheme all
  the same. `-askAssistant`, which hosts the assistant in place of the library, and `-askHoldTurn`,
  which holds every turn in flight, aren't in the schemes: add one to a scheme's Run arguments in Xcode,
  or pass it at launch.
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

The README's `docs/images/mac.png` is a 960x560 window, which the thread fills, written after 8.5
seconds, which lands between blinks of the composer's caret. The first two arguments draw it light and
with the blue accent whatever the Mac's own settings are. Each `-key value` pair goes before any bare
flag, since AppKit pairs a `-`-prefixed argument with the next one:

```sh
caffeinate -dimsu AskKitDemo.app/Contents/MacOS/AskKitDemo \
  -NSRequiresAquaSystemAppearance YES -AppleAccentColor 4 \
  -askCaptureWindow /dev/fd/4 -askCaptureAfter 8.5 -askCaptureSize 960x560 4>mac.png
```
