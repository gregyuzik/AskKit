#if os(iOS) || os(macOS) || os(visionOS)

public import SwiftUI

extension EnvironmentValues {
    /// Whether the Ask screen under this view draws every answer at rest
    /// (`askDrawsAtRest(_:)`). False everywhere else.
    @Entry var askDrawsAtRest = false
}

extension View {
    /// Draws the Ask screen under this view at rest: what an answer brings
    /// (`askArrival`) is at full from its first frame, its prose is drawn
    /// without the reveal (`AskStreamingText`), and the screen moves nothing
    /// of its own, as under Reduce Motion (`AskScreen`).
    ///
    /// **For a UI test that reads the pixels**, such as an accessibility
    /// audit. Each of those motions runs on the wall clock, up to a second
    /// after an answer lands, and a test can't see one end: an audit that
    /// waited a fixed time for them could read a piece still coming up out of
    /// its blur on a Mac busy enough to draw late. Drawn at rest,
    /// there is nothing to wait for, and what is drawn is what a reader is
    /// left with once the motion is over.
    ///
    /// Not Reduce Motion itself, which keeps a fade, and which the system's
    /// own views read too. False leaves the motion as it is.
    @_spi(AskKitInternal) public func askDrawsAtRest(_ drawsAtRest: Bool) -> some View {
        environment(\.askDrawsAtRest, drawsAtRest)
    }
}

#endif
