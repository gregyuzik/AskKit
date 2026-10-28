#if os(iOS) || os(macOS) || os(visionOS)

import SwiftUI
#if os(iOS)
import UIKit
#endif

/// How the screen puts the keyboard away (the composer's chevron, the bar's
/// Done, a tap on the screen and a turn starting), and how the first screen
/// makes room for it, in `change(_:to:duration:curve:in:)`.
///
/// **On iOS, through UIKit on the next turn of the main queue, not by writing
/// the focus binding.** Written in place, the binding can put the keyboard
/// away from inside the wrong update. In one host, with a 24 fps
/// `TimelineView` behind the screen, SwiftUI handled the chevron's write
/// inside the render that timeline's display link drives: the field resigned
/// mid-render, the hide animation opened around it, and the layout that
/// answers the keyboard (the composer dropping to the bottom edge, the first
/// screen's column re-centering) landed on the next display-link frame,
/// outside the animation. Recorded on a simulator and read frame by frame,
/// the column made its whole 123 pt trip in one frame on the chevron, on Done
/// and on the tap, while the keyboard was still sliding away. With the
/// timeline frozen, the same write was handled outside a render and the way
/// down tracked the keyboard. The demo doesn't show it, even over a 24 fps
/// `TimelineView` background, so the timeline alone isn't the whole trigger;
/// resigning on the next turn avoids it either way.
///
/// Resigning from the next main-queue turn hands the keyboard an idle
/// SwiftUI, and that is how the keyboard arrives: UIKit queues its show onto a
/// main-queue turn and lays the hosting view out inside the show's animation
/// block. Logged in that host with this resign, every layout pass on the way
/// down ran inside the hide's animation block too. Recorded, the chevron,
/// Done and the tap took 283, 273 and 273 ms with no step over 20 pt, against
/// 282 to 287 ms on the way up.
///
/// Two alternatives also recorded smooth, and aren't taken. Writing the
/// binding on the next turn depends on SwiftUI flushing that write from a
/// run-loop observer rather than a render, which is SwiftUI's scheduling to
/// decide. Resigning through UIKit in place animated from an update after the
/// hide's animation block rather than inside it.
///
/// **In the screen's own window** (`AskScreenWindow`), by `endEditing(true)`
/// on it, which resigns the first responder in that window and no other. The
/// action sent to no target that this replaces went to the first responder of
/// the app's key window, and with two windows up, on an iPad or iPhone Duo's
/// inner display, that needn't be this screen's: a turn starting here could
/// take the keyboard from a field the reader was typing in elsewhere, and
/// Done tapped in the window at the back, which comes to the front only after
/// the tap's action has run (`AskHostFocusHandOver`), could resign the field
/// in front. Read from UIKit's documented behavior, not seen on a device.
/// Where the caller has no window, as the composer's chevron doesn't, or
/// before the probe has joined one, the action still goes to the key
/// window's first responder.
///
/// The recordings above were of that action, sent from
/// `DispatchQueue.main.async`. A main-actor `Task` is queued on the same main
/// queue, and `endEditing(true)` resigns the same field; neither has been
/// recorded.
///
/// Focus follows the responder: SwiftUI clears the binding once the field has
/// resigned. On iOS alone: visionOS keeps the binding write, since nothing
/// here was measured on it, and the Mac has no software keyboard to put away.
enum AskKeyboard {
    #if os(iOS)
    static func putAway(_ isFocused: FocusState<Bool>.Binding, in screenWindow: AskScreenWindow? = nil) {
        Task {
            if let window = screenWindow?.window {
                window.endEditing(true)
            } else {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
                )
            }
        }
    }
    #else
    static func putAway(_ isFocused: FocusState<Bool>.Binding) {
        isFocused.wrappedValue = false
    }
    #endif

    #if os(iOS)
    /// Changes `flag` inside the animation the keyboard is running, over the
    /// `duration` and on the `curve` its show or hide message carries: the
    /// first screen making room (`AskScreen`'s `firstScreenMakesRoom`).
    ///
    /// **Two clocks, because the keyboard's can't reach inside the column.**
    /// Laid out inside this block, what the change does to the scroll view
    /// (its content size, and the inset that centers a column that fits) is
    /// animated by UIKit, which hands it to the render server on the keyboard's
    /// own curve and duration: that is the headline riding the keyboard. What
    /// the change does inside the column (the sentence and caveat gone, the
    /// gaps closed, the chips 102 pt nearer the headline) is SwiftUI's layout,
    /// which a UIKit animation can't move: with nothing else animating it, the
    /// chips made the whole trip in one frame while the headline glided. So
    /// `AskFirstScreen` animates that half itself, keyed on the flag.
    ///
    /// **The window is laid out inside the block** because a state change only
    /// marks the hosting view for layout, and the pass UIKit would run for it
    /// comes after the block has returned, outside the animation.
    ///
    /// **The column's half runs on the main thread, and can still step there.**
    /// SwiftUI's animation keeps time by the clock, so a frame the main thread
    /// misses is made up on the next one by however far the curve moved
    /// meanwhile; the headline's half, on the render server, misses nothing.
    /// Recorded on a simulator at 120 fps and read frame by frame over eight
    /// shows and eight dismisses, the headline moved at most 4.7 pt in a frame.
    /// The chips moved at most 8 pt in a frame while the main thread kept up,
    /// which on a simulator loaded by other work (load average 4 to 12) was
    /// three moves of the sixteen. On the rest, their first frame on a show
    /// came 88 to 155 ms after the headline began, while the keyboard did its
    /// own work, and gaps of 45 to 95 ms between their frames were made up in
    /// steps of as much as 35 pt. Nothing structural removes that: the closing
    /// up is layout, and layout doesn't run on the render server. It hasn't
    /// been recorded on a device.
    ///
    /// The curve arrives as 7, which `UIView.AnimationCurve` has no case for,
    /// and the typed message keeps it as the raw value: logged on the iOS 27.0
    /// simulator beside the keyboard notification, both say 7 and 0.3833 s on
    /// every show and hide. `UIView.AnimationOptions` keeps its curve from bit
    /// 16 up, where the four public curves are 0 to 3, so the raw value shifted
    /// there is the keyboard's own curve rather than the nearest public one.
    ///
    /// **The screen's own window**, which `AskScreen` hands in as its
    /// `AskWindowHeightReader` probe found it (`AskScreenWindow`). With two
    /// scenes up, such as two windows on an iPad or iPhone Duo's inner
    /// display, the key window can be another scene's: the layout pass would
    /// run there, and this screen's column would land outside the keyboard's
    /// animation. The key window, found across every connected scene, stands
    /// in only where the caller has none, such as before the probe has joined
    /// a window.
    static func change(
        _ flag: Binding<Bool>,
        to value: Bool,
        duration: TimeInterval,
        curve: UIView.AnimationCurve,
        in screenWindow: UIWindow? = nil
    ) {
        let window = screenWindow ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: UIView.AnimationOptions(rawValue: UInt(clamping: curve.rawValue) << 16)
        ) {
            flag.wrappedValue = value
            window?.layoutIfNeeded()
        }
    }
    #endif
}

#endif
