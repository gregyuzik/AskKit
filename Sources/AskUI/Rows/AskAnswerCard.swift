#if os(iOS) || os(macOS) || os(visionOS)

public import SwiftUI

/// The card under an answer, whatever sits in it (a host's payload view, such
/// as a chart or a status strip, or the confirmation card for something the
/// answer offers to do), so they read as one family rather than separate
/// inventions.
///
/// **Content, so a fill and never glass.** It sits in the thread with the prose
/// and the tiles, under the navigation layer where glass lives. A hairline
/// says where it ends, and Increase Contrast makes that hairline a line.
///
/// **Concentric corners.** Inside a container with a shape of its own (a
/// sheet, a snippet, a window) the card's corners follow it; in the thread,
/// where there is none, they fall back to `minimumRadius`.
public struct AskAnswerCard<Content: View>: View {
    private let content: Content

    @Environment(\.colorSchemeContrast) private var contrast

    /// The corner radius where no container supplies one.
    public static var minimumRadius: CGFloat { 16 }

    /// A card around `content`, padded and as wide as the space it is offered.
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        let shape = ConcentricRectangle(corners: .concentric(minimum: .fixed(Self.minimumRadius)), isUniform: true)
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.fill.quaternary, in: shape)
            .overlay {
                shape.stroke(
                    contrast == .increased ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary),
                    lineWidth: contrast == .increased ? 1 : 0.5
                )
            }
            .accessibilityElement(children: .contain)
    }
}

#endif
