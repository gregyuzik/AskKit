#if os(iOS) || os(macOS) || os(visionOS)

public import SwiftUI

extension EnvironmentValues {
    /// Whether the host has pushed an item over the Ask screen, from the
    /// update that pushes it until the one that pops it.
    ///
    /// Set it on the screen from the state the push itself reads, such as
    /// `detail != nil` for a `navigationDestination(item:)` or `!path.isEmpty`
    /// for a path, so it changes in the push's own update and never after it.
    /// The screen keeps its navigation bar open while it's true
    /// (`AskNavigationBarMinimization`). It's false by default, so a host that
    /// never pushes over the screen keeps a bar that minimizes.
    @Entry public var askItemIsPushed = false
}

/// Whether the screen's navigation bar may minimize as the reader scrolls
/// down, which is `toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)`
/// on iOS. It sits apart from the view so the package's tests, which run on
/// the Mac, can check it.
///
/// **Open while Done shows.** Done is one of the bar's items, and a minimized
/// bar hides its items, so the keyboard would come up under a bar with nothing
/// in it.
///
/// **Open while an item is pushed over the screen.** A page pushed while the
/// bar is minimized hangs the app. The push lays the page out once before it
/// moves, and that pass never ends: the page's scroll view takes the
/// minimized bar's insets, the new insets move its content offset, the
/// navigation controller lays the bar out again for that offset, and the bar
/// changes the insets again. The scene then misses its 10-second
/// watchdog (0x8BADF00D). A host app hit it twice on an iPhone 17 Pro, from
/// a tile under an answer. On an iPhone 18 Pro simulator it hung with the zoom
/// and with a plain push, and marking the pushed page `.never` didn't help.
/// Holding this screen's bar open in the push's own update opened the page
/// normally. Only the host knows when it pushes, so it says so
/// (`askItemIsPushed`).
///
/// **Open while the thread moves on the screen's own scroll**, and for a beat
/// after (`AskScreen.threadScrollsItself`): a question landing at the foot, a
/// chat opened, the follow, the pill's jump, a resize keeping the foot.
/// `.onScrollDown` reads the scroll view's offset, not whose scroll moved it,
/// so the screen's own scroll down minimized the bar too. Measured on the demo
/// on an iPhone 18 Pro simulator, iOS 27.2: an earlier chat opened from the
/// pane beside a fold minimized the bar every time, taking the gear item away
/// and moving the pane of chats up 54 pt, and following three answers to the
/// foot minimized it in one run of three. Only the reader's scroll minimizes
/// it. A bar already minimized is left so (`AskScrollFollow.barLooksMinimized`):
/// `.never` would open it.
///
/// "Minimizes", the SDK's word, because AskKit keeps "fold" for iPhone Duo's
/// hinge (ARCHITECTURE.md, Words kept to one meaning).
nonisolated enum AskNavigationBarMinimization {
    static func minimizes(showsDoneItem: Bool, itemIsPushed: Bool, threadScrollsItself: Bool) -> Bool {
        !showsDoneItem && !itemIsPushed && !threadScrollsItself
    }
}

#endif
