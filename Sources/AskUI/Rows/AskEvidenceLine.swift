#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import SwiftUI

/// What the answer read, under the tiles.
///
/// **Attribution, always.** Every answer says what it stood on: never a
/// percentage, never a confidence score. By default that is how much of the
/// reader's own data it read, the count and where it came from, including on
/// an answer that shows no tiles: a count question reads a hundred rows and
/// shows none of them, and is exactly the answer a reader most wants the
/// basis for. An answer nothing grounded says so instead ("Not from this
/// app's data"), so prose a `.notRequired` domain keeps never passes for an
/// answer that read the reader's data.
///
/// **The words are the domain's, and what the line opens onto is AskKit's**
/// (`AskDomain.evidence(for:)`). A domain whose rows aren't items words the
/// line itself, and one that attributes its answers another way leaves it
/// out; either wins over the ungrounded line.
///
/// **The chevron appears only when there is something behind it.** `isExpanded`
/// is a binding the thread passes only when the host supplies an
/// `evidenceDisclosure` to draw the rows, and the line takes it only when there
/// are rows behind its words (`Content.opensOntoRows`). Otherwise the line
/// stays a plain line, because a chevron that opens onto nothing is worse than
/// no chevron. The ungrounded line is always plain: nothing grounded the
/// answer, so whatever rows it carries aren't what it stood on.
struct AskEvidenceLine: View {
    private let content: Content?
    private let isExpanded: Binding<Bool>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Whether the reader has Button Shapes on, which underlines the line's
    /// words where it is a button (`AskBareButtonShape`).
    @Environment(\.accessibilityShowBorders) private var showsBorders

    init(content: Content?, isExpanded: Binding<Bool>? = nil) {
        self.content = content
        self.isExpanded = isExpanded
    }

    var body: some View {
        if let content {
            let label = Self.label(content)
            if let isExpanded, content.opensOntoRows {
                Button {
                    withAnimation(reduceMotion ? .none : .snappy(duration: 0.22)) {
                        isExpanded.wrappedValue.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        // Words alone, so underlined under Button Shapes.
                        // The plain line below is text, and isn't.
                        label.underline(AskBareButtonShape.underlines(showsBorders: showsBorders))
                        // A swap, not a `rotationEffect`. A rotation isn't
                        // mirrored in a right-to-left layout, so a +90° turn
                        // that points down in English points *up* in Hebrew,
                        // and `chevron.right` points back into its own label
                        // there before it turns at all. `chevron.forward`
                        // mirrors, and the two glyphs say the state outright.
                        Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.forward")
                            .font(.caption2)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .askDeemphasizedText()
                    // The drawn line is caption-sized, roughly 16 pt. The
                    // target isn't: `contentShape` makes the whole band of a
                    // touch target, 44 pt and 60 on visionOS
                    // (`AskGrowth.touchTarget`), tappable without changing
                    // what the reader sees.
                    .frame(minHeight: AskGrowth.touchTarget)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                // The whole band lit, its ends round: what a tap on it lands
                // on. No help tag: the words say what the line is, and the
                // hint below says what a tap does, which `.help` would take.
                .askHoverEffect(in: .capsule)
                .accessibilityLabel(label)
                // Not `.isSelected`, which VoiceOver speaks as "selected": the
                // line isn't selected, it is expanded or collapsed, and the
                // hint is what says it can be acted on at all.
                .accessibilityValue(Self.expansionValue(isExpanded.wrappedValue))
                .accessibilityHint(Self.expansionHint)
                .accessibilityIdentifier(AskAccessibility.evidence)
            } else {
                // Text, which VoiceOver reads as text: the ungrounded line,
                // and any line with nothing to open.
                label.askDeemphasizedText()
                    .accessibilityIdentifier(AskAccessibility.evidence)
            }
        }
    }

    private static func expansionValue(_ expanded: Bool) -> Text {
        expanded
            ? Text("Expanded", bundle: #bundle, comment: "VoiceOver value for the Ask evidence line when what the answer read is showing beneath it.")
            : Text("Collapsed", bundle: #bundle, comment: "VoiceOver value for the Ask evidence line when what the answer read is hidden.")
    }

    /// Said of the line whichever words it reads, AskKit's count or the
    /// domain's own, so it names no kind of thing.
    private static var expansionHint: Text {
        Text(
            "Shows what this answer read",
            bundle: #bundle,
            comment: "VoiceOver hint on the evidence line under an Ask answer, which reads From 3 items or the app's own words about where the answer came from. Activating it shows, beneath the line, what the answer read."
        )
    }

    private static func label(_ content: Content) -> Text {
        switch content {
        case .counted(let count, let scope?):
            Text(
                "From ^[\(count) item](inflect: true) in your \(scope)",
                bundle: #bundle,
                comment: "Attribution under an Ask answer: how many of the reader's own items it read, and which part of their library they came from. The second placeholder is that part's name."
            )
            .font(.caption)
        case .counted(let count, nil):
            Text(
                "From ^[\(count) item](inflect: true)",
                bundle: #bundle,
                comment: "Attribution under an Ask answer: how many of the reader's own items it read."
            )
            .font(.caption)
        case .worded(let words, _):
            // Resolved by the domain, so drawn as it is and never looked up.
            Text(verbatim: words)
                .font(.caption)
        case .ungrounded:
            Text(
                "Not from this app's data",
                bundle: #bundle,
                comment: "Attribution under an Ask answer that nothing in the app grounded: the model answered from the conversation or what it knows, without reading the reader's items or using the app's tools. Shown where the line saying how many items an answer read would be. A neutral statement of fact, not a warning, in small secondary text."
            )
            .font(.caption)
        }
    }
}

extension AskEvidenceLine {
    /// What the line says, and whether it opens onto the rows behind the
    /// answer: decided apart from the view so it can be tested
    /// (`AskEvidenceLineTests`). Nil is no line.
    nonisolated enum Content: Equatable {
        /// AskKit's count, with the domain's scope when it names one: "From 3
        /// items", "From 3 items in your Vinyl Records". Only ever more than
        /// zero.
        case counted(Int, scope: String?)
        /// The domain's own words (`AskEvidencePresentation.line`), over the
        /// number of rows behind the answer, which may be none.
        case worded(String, rowsBehind: Int)
        /// "Not from this app's data": an answer nothing grounded, under a
        /// domain that leaves the line to AskKit.
        case ungrounded

        /// What the line under `answer` says, as `domain` presents it.
        init?<Domain: AskDomain>(answer: AskAnswer<Domain.Row>, domain: Domain) {
            self.init(
                presentation: domain.evidence(for: answer),
                grounding: answer.grounding,
                rowsBehind: answer.matches.count,
                scope: domain.evidenceScope(from: answer)
            )
        }

        /// The decision itself.
        ///
        /// **The domain's choice first**, so its `.line` and `.hidden` win over
        /// the ungrounded line. Under `.counted`, an answer nothing grounded
        /// says so in place of a count, whatever rows it carries: an
        /// ungrounded follow-up carries the thread's rows as its matches
        /// (`AskAnswer.matches`), and they didn't ground it.
        ///
        /// **No grounding recorded is not `AskGrounding.nothing`.** A turn the
        /// reader stopped and one from a thread saved before answers recorded
        /// their grounding have nil, and so, usually, does an answer the domain
        /// gave without a model, unless the domain set one; all of those are
        /// counted as before. Unknown is not a claim.
        ///
        /// `scope` is asked only for the counted line, the one that names it.
        init?(
            presentation: AskEvidencePresentation,
            grounding: AskGrounding?,
            rowsBehind: Int,
            scope: @autoclosure () -> String?
        ) {
            switch presentation {
            case .hidden:
                return nil
            case .line(let words):
                // A line with no words would still take the thread's spacing
                // and VoiceOver's attention, and say nothing.
                guard !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                self = .worded(words, rowsBehind: rowsBehind)
            case .counted:
                if grounding == .nothing {
                    self = .ungrounded
                } else if rowsBehind > 0 {
                    self = .counted(rowsBehind, scope: scope())
                } else {
                    return nil
                }
            }
        }

        /// Whether a chevron may open the rows behind the answer under this
        /// line: there are some, and the line speaks for them. Never the
        /// ungrounded line's.
        var opensOntoRows: Bool {
            switch self {
            case .counted: true
            case .worded(_, let rowsBehind): rowsBehind > 0
            case .ungrounded: false
            }
        }
    }
}

#endif
