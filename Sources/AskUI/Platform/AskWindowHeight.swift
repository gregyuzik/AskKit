#if os(iOS)
import SwiftUI
import UIKit

/// Reports the height of the window the screen is in, for the first screen to
/// arrange itself by (`AskFirstScreen.isSideBySide`), and keeps that window
/// for the keyboard (`AskScreenWindow`).
///
/// **UIKit, because nothing in SwiftUI gives a height the keyboard leaves
/// alone.** A view behind the screen that ignored every safe area, the
/// keyboard's included, still shrank with the keyboard: in a maximized iPad
/// window it read 1270 at rest and 887 with the keyboard up, since the
/// container above it shrinks, not only its safe area. It also stopped at the
/// navigation bar, and as the demo launched it reported 54, then 683, before
/// coming to rest at 799, which would have put a tall window's first screen
/// side by side for a frame. A window's bounds change only when the window
/// does.
///
/// The height is reported from a main-actor task, on a later turn of the
/// main queue and never from inside a layout pass, and only when it changes.
/// The window is kept at once, since nothing redraws on it.
struct AskWindowHeightReader: UIViewRepresentable {
    /// Where the window the screen is in is kept, or nil to keep it nowhere.
    var window: AskScreenWindow?
    let onChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.isUserInteractionEnabled = false
        probe.onChange = onChange
        probe.screenWindow = window
        return probe
    }

    func updateUIView(_ probe: Probe, context: Context) {
        probe.onChange = onChange
        probe.screenWindow = window
    }

    /// Asks its window for its height whenever it joins one or is laid out,
    /// which a window's resize always causes: this view is the size of the
    /// screen it sits behind.
    final class Probe: UIView {
        var onChange: ((CGFloat) -> Void)?
        /// Handed the window this view joins, and nil as it leaves one.
        var screenWindow: AskScreenWindow? {
            didSet { screenWindow?.window = window }
        }
        private var reported: CGFloat = 0

        override func didMoveToWindow() {
            super.didMoveToWindow()
            screenWindow?.window = window
            report()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        private func report() {
            guard let height = window?.bounds.height, height != reported else { return }
            reported = height
            Task { [weak self] in self?.onChange?(height) }
        }
    }
}

/// The window an `AskScreen` is in, as `AskWindowHeightReader`'s probe finds
/// it: where the keyboard's change lays out
/// (`AskKeyboard.change(_:to:duration:curve:in:)`), and where the screen
/// puts its keyboard away (`AskKeyboard.putAway(_:in:)`).
///
/// **A reference the keyboard's observers hold**, since they are made once,
/// as the screen first appears, and read the window when the keyboard moves,
/// which is after it has joined one. A put-away reads it as it resigns. **Weak**, because the window holds the
/// screen's hosting view, and so the state that holds this: held strongly, a
/// closed window would never go.
final class AskScreenWindow {
    weak var window: UIWindow?
}
#endif
