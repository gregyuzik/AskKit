# Tips

For changing AskUI's tips and walking them. What the three tips are, the rule each obeys and where they
are gated are in [docs/ARCHITECTURE.md](../../docs/ARCHITECTURE.md#tips); why each is as it is, with the
measurements, is in the doc comments of `AskTips.swift`, `AskScreen.swift`'s tip gates, `AskFirstScreen`,
`AskQuestionBubble`, `AskThreadHistoryList` and `AskChatsPane`.

## The walk

The placements were walked on 2026-10-31 on the iPhone 18 Pro, iPad mini (A17 Pro), iPhone Duo and Apple
Vision Pro simulators (27.2) and on macOS 27.2. Beside what the comments hold:

- The starter's tip stands above "Try asking", its arrow on the heading, on every device and in every Duo
  pose: on the outer display on its side, in a tabletop below the fold, in a book on the thread's side of
  it.
- On visionOS a window resize settles the gates again, and each return counts as a display, which costs
  nothing while no tip has a `MaxDisplayCount`.

## Left as they are

- In a tabletop, the chats sheet's tip rides up over its own row: the system moves a popover clear of
  the fold whatever its source, and under the row there is no room above the fold.
- Open flat on its side, the question tip under its question crosses the divider into the chats pane by
  9 pt, clear of the chats. On the outer display on its side, the system's leading placement lays the
  arrow's tip on the bubble's first letter.
- Closing iPhone Duo with the keyboard up hides the keyboard for up to a second under load, as the
  scene moves displays, and the starter's gate can open in the gap; it closed again 377 ms later,
  before TipKit had shown anything.
- At compact width in Hebrew the question popover is a few points short of its text, by TipKit's
  sizing; no text is lost.
- On visionOS in a narrow window the question popover overhangs the window, which visionOS allows; its
  × stays in reach.
- The Mac's popover keeps the width its text asks for, so in a window 380 pt wide the question tip
  hangs 125 pt past the window's trailing edge.
