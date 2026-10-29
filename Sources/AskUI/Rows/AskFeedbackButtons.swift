#if os(iOS) || os(macOS) || os(visionOS)

public import AskCore
public import SwiftUI

/// Two thumbs under an answer: voluntary, one tap, low emphasis.
///
/// Where a verdict goes is the store's business (`AskConversationStore.rate`):
/// the log always, and a feedback attachment for the newest model answer while
/// its session is kept. This is only the control.
///
/// **Glyphs, not bordered buttons.** A bordered pair under every answer would
/// out-shout the evidence line beside it, which is the line a reader actually
/// needs. Secondary until chosen; the chosen one fills. The hit region is a
/// full target around a caption-sized glyph: 44 pt, 60 on visionOS, or 28 on
/// the Mac, where a pointer does the aiming. A reader who has Button Shapes on
/// gets a ring round each glyph (`AskBareButtonShape`).
///
/// **The target grows by what the glyph grows, not in proportion to it**
/// (`AskFeedbackTarget`). In proportion, the 16 pt around a 12 pt glyph is
/// 51 pt around one of 38 at the largest text size: the pair is 281 pt wide
/// in a phone's column of 366, and the evidence line beside it is left a
/// character's width.
struct AskFeedbackButtons: View {
    private let selection: AskFeedback.Sentiment?
    private let onRate: (AskFeedback.Sentiment) -> Void

    /// The glyph's size as the text scales it: `.caption`, 12 pt at the
    /// default size.
    @ScaledMetric(relativeTo: .caption) private var glyph: CGFloat = AskFeedbackTarget.glyph
    /// Whether the reader has Button Shapes on, which rings each thumb
    /// (`AskBareButtonShape`).
    @Environment(\.accessibilityShowBorders) private var showsBorders

    private var target: CGFloat { AskFeedbackTarget.side(glyph: glyph) }

    init(selection: AskFeedback.Sentiment?, onRate: @escaping (AskFeedback.Sentiment) -> Void) {
        self.selection = selection
        self.onRate = onRate
    }

    var body: some View {
        HStack(spacing: 0) {
            thumb(.positive)
            thumb(.negative)
        }
    }

    private func thumb(_ sentiment: AskFeedback.Sentiment) -> some View {
        let chosen = selection == sentiment
        return Button {
            onRate(sentiment)
        } label: {
            Image(systemName: Self.symbol(for: sentiment, chosen: chosen))
                .font(.caption)
                // **A ring round the glyph under Button Shapes, not round
                // the target**: the two targets touch, and rings their size
                // would run into each other.
                .padding(AskBareButtonShape.ringInset)
                .askButtonShapeRing(.capsule, showsBorders: showsBorders)
                .frame(width: target, height: target)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // A circle the target's size: the pair is two lights side by side,
        // not one bar.
        .askHoverEffect(in: .circle)
        .foregroundStyle(chosen ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .accessibilityLabel(Self.label(for: sentiment))
        .askHelp(Self.label(for: sentiment))
        // What Voice Control answers to: the label, and the name of the
        // glyph a reader sees.
        .accessibilityInputLabels([Self.label(for: sentiment), Self.glyphName(for: sentiment)])
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier(
            sentiment == .positive ? AskAccessibility.feedbackPositive : AskAccessibility.feedbackNegative
        )
    }

    static func symbol(for sentiment: AskFeedback.Sentiment, chosen: Bool) -> String {
        switch sentiment {
        case .positive: chosen ? "hand.thumbsup.fill" : "hand.thumbsup"
        case .negative: chosen ? "hand.thumbsdown.fill" : "hand.thumbsdown"
        }
    }

    /// What VoiceOver calls a thumb, and the Mac's help tag on it.
    static func label(for sentiment: AskFeedback.Sentiment) -> Text {
        switch sentiment {
        case .positive:
            Text("Helpful", bundle: #bundle, comment: "VoiceOver label for the thumbs-up under an Ask answer: tells the app the answer helped.")
        case .negative:
            Text("Not helpful", bundle: #bundle, comment: "VoiceOver label for the thumbs-down under an Ask answer: tells the app the answer did not help.")
        }
    }

    private static func glyphName(for sentiment: AskFeedback.Sentiment) -> Text {
        switch sentiment {
        case .positive:
            Text("Thumbs up", bundle: #bundle, comment: "Voice Control name for the thumbs-up under an Ask answer, beside its VoiceOver label 'Helpful'.")
        case .negative:
            Text("Thumbs down", bundle: #bundle, comment: "Voice Control name for the thumbs-down under an Ask answer, beside its VoiceOver label 'Not helpful'.")
        }
    }
}

/// How wide and tall a thumb's hit region is, apart from the view so the rule
/// can be pinned (`AskLargeTextTests`).
nonisolated enum AskFeedbackTarget {
    /// The glyph at the default text size: `.caption`.
    static let glyph: CGFloat = 12

    /// The target at the default text size, and the least it is at any: a
    /// touch target, 60 pt on visionOS (`AskGrowth.touchTarget`), and 28 on
    /// the Mac.
    #if os(macOS)
    static let minimum: CGFloat = 28
    #else
    static let minimum: CGFloat = AskGrowth.touchTarget
    #endif

    /// The target around a glyph of the given size: the room the default
    /// size leaves around its glyph, kept as it is around a larger one.
    static func side(glyph scaled: CGFloat) -> CGFloat {
        AskGrowth.grown(minimum, glyph: glyph, scaled: scaled)
    }
}

#endif
