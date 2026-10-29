#if os(iOS) || os(macOS) || os(visionOS)

public import SwiftUI

/// A picture that can land after the view it sits in is already drawn (a photo
/// still decoding, an icon still on its way, a thumbnail read back from disk)
/// **comes into focus over its placeholder, the way an answer's pieces arrive**
/// (`AskArrival`), instead of cutting in over it in a single frame.
///
/// The loading stays the host's: hand this what it has so far, nil until then.
/// The crossing is this view's, on a piece's own blur, scale and curve.
///
/// **Only a picture landing or leaving moves.** A picture that is there when the
/// view is built, such as a cache hit or a photo already in memory, is drawn at
/// rest in its first frame, since there is nothing for it to arrive from. One
/// that lands later comes in however late it is, unlike a piece, which arrives
/// only for the answer that has just ended: a picture that pops reads as a pop
/// whether its answer landed a second ago or a day ago. One that goes, leaving
/// its placeholder, crosses back out the same way. A picture swapped for
/// another under the same tile is a swap, and is drawn without moving.
///
/// **Frame this view, not the two views inside it**, so the picture and its
/// placeholder take the same size, and a tile holds its shape while its picture
/// loads.
///
/// Reduce Motion keeps the fade and drops the blur and the scale, as a piece does.
public struct AskPictureArrival<Value, Picture: View, Placeholder: View>: View {
    private let value: Value?
    private let picture: (Value) -> Picture
    private let placeholder: () -> Placeholder

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A picture drawn from `value` once there is one, crossing over its
    /// placeholder when it lands.
    ///
    /// - Parameters:
    ///   - value: What the picture is drawn from, or nil while it is still
    ///     loading or when there is none.
    ///   - picture: The picture, drawn from `value`.
    ///   - placeholder: What stands in the picture's place until then.
    public init(
        _ value: Value?,
        @ViewBuilder picture: @escaping (Value) -> Picture,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.value = value
        self.picture = picture
        self.placeholder = placeholder
    }

    public var body: some View {
        // A `ZStack`, so the picture is laid over its placeholder while the two
        // cross. A `Group` would lend both to the caller's stack for the length
        // of the transition: in a card's `VStack`, the outgoing placeholder
        // stands above the incoming photo, and the tile jumps twice.
        ZStack {
            if let value {
                picture(value)
                    .transition(crossing)
            } else {
                placeholder()
                    .transition(crossing)
            }
        }
        // Keyed on whether there is a picture rather than on the picture, so a
        // picture landing or leaving animates and one swapped for another does
        // not.
        .animation(AskArrival.animation(for: .piece, step: 0, reduceMotion: reduceMotion), value: value != nil)
    }

    /// How the picture and its placeholder cross: a piece's own blur, scale and
    /// fade, run as a transition, or the fade alone under Reduce Motion.
    private var crossing: AnyTransition {
        guard !reduceMotion else { return AnyTransition(.opacity) }
        return .modifier(
            active: AskPictureCrossing(blur: AskArrival.blur(for: .piece), scale: AskArrival.scale, opacity: 0),
            identity: AskPictureCrossing(blur: 0, scale: 1, opacity: 1)
        )
    }
}

/// The three effects a crossing draws with, none of which moves a frame.
private struct AskPictureCrossing: ViewModifier {
    let blur: CGFloat
    let scale: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .scaleEffect(scale)
            .opacity(opacity)
    }
}

#endif
