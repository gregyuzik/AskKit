#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import SwiftUI

/// What the turn is doing while the reader waits.
///
/// **The phrases are the tools' own reports, never a timer.** The stretch before
/// the first word of prose is tool calls and reasoning, and it can run for
/// seconds. One unchanging line would be true and say nothing, for the same
/// number of seconds whether the model read four rows or four hundred. Nothing
/// here invents a stage or paces a delay to have something to show.
///
/// The shimmer is the row's one ornament, in the accent whatever the host's
/// spectrum, which only the send circle and the caret wear (`AskSpectrum`).
/// It goes under Reduce Motion: a mask sweeping a gradient is motion by any
/// reading.
///
/// **Two lines, and the upper one is the phrase this one replaced**
/// (`AskWaitWindow`). A grounded turn moves through phrases, and a row that
/// kept only the last would say the turn is busy without ever saying it got
/// anywhere.
struct AskThinkingRow<Mark: View>: View {
    private let phrase: String
    private let rowsRead: Int
    private let accent: Color
    private let takesFocus: Bool
    private let onFocusTaken: () -> Void
    private let onStop: () -> Void
    private let mark: Mark

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var markSize: CGFloat = 26
    @State private var window = AskWaitWindow()
    /// VoiceOver's focus on the row. Held by `AskThreadRow`, which outlives
    /// the row, so it can tell whether the row had the focus as it went
    /// (`AskWaitRowHandoff`).
    @AccessibilityFocusState.Binding private var isFocused: Bool

    /// - Parameters:
    ///   - hasVoiceOver: Whether VoiceOver's focus is on the row, held by the
    ///     caller.
    ///   - takesFocus: Whether the row takes VoiceOver's focus as it appears:
    ///     on a turn started from a control that went as it started, such as
    ///     Try Again (`AskThreadList.waitRowFocus`), or as it comes back in
    ///     place of prose that had the focus when the turn restarted
    ///     (`AskWaitRowHandoff.returning(proseHadFocus:to:)`).
    ///   - onFocusTaken: Called once the row has taken it.
    ///   - onStop: Stops the turn: VoiceOver's Magic Tap on the row.
    init(
        phrase: String,
        rowsRead: Int,
        accent: Color,
        hasVoiceOver: AccessibilityFocusState<Bool>.Binding,
        takesFocus: Bool = false,
        onFocusTaken: @escaping () -> Void = {},
        onStop: @escaping () -> Void = {},
        @ViewBuilder mark: () -> Mark
    ) {
        self.phrase = phrase
        self.rowsRead = rowsRead
        self.accent = accent
        _isFocused = hasVoiceOver
        self.takesFocus = takesFocus
        self.onFocusTaken = onFocusTaken
        self.onStop = onStop
        self.mark = mark()
    }

    var body: some View {
        // The earlier phrase sits above the mark's row rather than inside it,
        // so the mark keeps its place beside the live line. With both lines
        // beside one centered mark, the glyph would drop half a line the moment
        // a second phrase arrived.
        VStack(alignment: .leading, spacing: 2) {
            earlierLine
            HStack(spacing: 10) {
                mark
                    .frame(width: markSize, height: markSize)
                Text(shownLine)
                    .font(.subheadline)
                    .askDeemphasizedText()
                    .contentTransition(.opacity)
                    .modifier(ShimmerSweep(active: !reduceMotion, accent: accent, isLight: colorScheme == .light))
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        // The live line only. The phrase above it is a trail the eye reads, and
        // feeding it to VoiceOver would make `updatesFrequently` re-read history
        // over a reader who has already heard it.
        //
        // **The phrase as the label and the count as the value**, rather than
        // the line as drawn, whose middle dot is typography for the eye and
        // punctuation VoiceOver may speak. A label and a value are read with
        // the pause between them a reader expects.
        .accessibilityLabel(phrase)
        .accessibilityValue(read ?? "")
        // Tells VoiceOver to re-read this element as it changes rather than
        // treating each phrase as a new thing to announce over the reader.
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier(AskAccessibility.thinking)
        .accessibilityFocused($isFocused)
        // **Magic Tap stops the turn.** A VoiceOver reader waiting here
        // otherwise has to move to the stop circle in the composer, taking
        // the focus from the row, so the line that says they stopped it never
        // receives it (`AskWaitRowHandoff`). The row is there only while a
        // turn is in flight, so the gesture is taken from nothing else at any
        // other time. The Mac has no Magic Tap, and ⌘. stops a turn there.
        #if !os(macOS)
        .accessibilityAction(.magicTap, onStop)
        #endif
        // In a task rather than in `onAppear`, so the row is in the
        // accessibility tree by the time the focus is asked for. Not watched
        // under VoiceOver: no simulator runs it.
        .task(id: takesFocus) {
            guard takesFocus else { return }
            isFocused = true
            onFocusTaken()
        }
        // **On the phrase, never on `shownLine`** (`AskWaitWindow.advanced(to:)`
        // says why): `shownLine` carries the rows-read count, which ticks
        // constantly inside one activity.
        .onAppear { window = window.advanced(to: phrase) }
        .onChange(of: phrase) { _, arrived in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                window = window.advanced(to: arrived)
            }
        }
    }

    /// The phrase the live one replaced, or the space it will occupy.
    ///
    /// **Drawn empty rather than not drawn at all.** An empty `Text` still
    /// reserves its line, so the row stands at its full height from the first
    /// frame and the thread under it never moves when a second phrase lands
    /// (house rule 4). `AskTierCaption` makes the same reservation with
    /// `Text(verbatim: "")` to stop the navigation bar changing height mid-turn.
    /// Measured at `.subheadline` in an `NSHostingView`: 30 pt with the upper
    /// line empty, 30 pt with it filled, against 14 pt for one line alone.
    ///
    /// **`verbatim` because the phrase is already localized:** either
    /// `AskActivityPhrase` resolved it or the domain wrote it.
    ///
    /// **0.45 is a trail, and Increase Contrast takes it back to full.** It
    /// multiplies the alpha `askDeemphasizedText` already draws in, so on
    /// iOS the line lands at about 1.9:1 on white (the gray at 0.76, by 0.45)
    /// and 2.0:1 on a phone's black (`.secondary`'s 0.6, by 0.45), well under
    /// the bar for text a reader has to read. Don't "fix" it to full for
    /// everyone: this line is superseded, it is `accessibilityHidden`, and the
    /// reader who asked for contrast already gets it at full strength. Two
    /// steps rather than one, exactly as `AskDeemphasizedText` itself reasons.
    ///
    /// One line, truncated if it must be. `AskChipRow` argues against
    /// truncation for a question the reader is being asked to choose; this is
    /// neither a question nor current, and a fixed line is what holds the height.
    private var earlierLine: some View {
        Text(verbatim: window.previous ?? "")
            .font(.subheadline)
            .askDeemphasizedText()
            .opacity(contrast == .increased ? 1 : 0.45)
            .lineLimit(1)
            .padding(.leading, markSize + 10)
            .accessibilityHidden(true)
    }

    /// The live line as drawn: the phrase, and how many items the turn has
    /// read once it has read any.
    private var shownLine: String {
        AskWaitRowLine.joining(phrase, read: read)
    }

    /// How many items the turn has read, or nil before it has read any.
    private var read: String? {
        guard rowsRead > 0 else { return nil }
        return String(
            localized: "\(rowsRead) read",
            bundle: #bundle,
            comment: "Appended to the Ask wait row: how many of the reader's own items the turn has read so far."
        )
    }
}

/// The wait row's live line as drawn, apart from the view so it can be tested.
nonisolated enum AskWaitRowLine {
    /// `phrase`, and `read` after it where there is a count to show, joined as
    /// the reader's language joins two parts of one line: the separator is the
    /// catalog's, so a locale with a mark of its own uses it.
    static func joining(_ phrase: String, read: String?) -> String {
        guard let read else { return phrase }
        return String(
            localized: "\(phrase) · \(read)",
            bundle: #bundle,
            comment: "The Ask wait row's live line: what the turn is doing, such as \"Searching your records\", then how many of the reader's own items it has read so far, such as \"12 read\". The middle dot only separates the two; use the separator your language puts between two short parts of one line."
        )
    }
}

/// A gradient mask sweeping across whatever it is applied to.
///
/// Not an imitation of the system's Apple Intelligence shimmer: a plain
/// highlight sweeping across one line of secondary text, at 30 fps rather than
/// the display's rate, because nobody is reading it closely and a wait row
/// shouldn't cost a full-rate timeline.
///
/// **In reading direction.** The band runs from the leading edge to the
/// trailing one, and a `LinearGradient` from `.leading` to `.trailing` is
/// mirrored in a right-to-left layout, so in Hebrew and Arabic it sweeps from
/// the right (`AskShimmerTests`).
///
/// **The band lightens the line, so in light mode it is as strong as the line's
/// contrast lets it be** (`strength(for:isLight:)`). Added over the
/// deemphasized gray on white, the accent at 0.55 took the line from 5.31:1
/// to 2.17:1 as it passed, for the system blue.
struct ShimmerSweep: ViewModifier {
    let active: Bool
    let accent: Color
    let isLight: Bool

    func body(content: Content) -> some View {
        if active {
            let band = accent.opacity(strength)
            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 1.6) / 1.6
                content.overlay {
                    Self.band(at: phase, color: band)
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                        .mask { content }
                }
            }
        } else {
            content
        }
    }

    /// The band at `phase`, 0 at the leading edge and 1 at the trailing one.
    static func band(at phase: Double, color: Color) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .clear, location: max(0, phase - 0.15)),
                .init(color: color, location: phase),
                .init(color: .clear, location: min(1, phase + 0.15))
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// The accent in the appearance the row is drawn in, at the band's
    /// strength.
    private var strength: Double {
        var environment = EnvironmentValues()
        environment.colorScheme = isLight ? .light : .dark
        return Self.strength(for: AskContrast.RGB(accent.resolve(in: environment)), isLight: isLight)
    }

    /// The band's strength at its peak in dark mode, where lightening the line
    /// only takes it further from the dark ground.
    static let darkStrength = 0.55

    /// How strongly the band wears the accent: `darkStrength` in dark mode,
    /// and in light mode the most, in hundredths, that keeps the line at
    /// 4.5:1 on white where the band adds the accent to it (`.plusLighter`).
    /// 0.09 for the system blue (#0088FF) and 0.05 for yellow (#FFD60A): a
    /// faint sheen, which is what the line's contrast leaves room for. Worked
    /// out on the line's own gray (`AskContrast.deemphasizedLight`); under
    /// Increase Contrast the line is `.primary`, and holds more.
    static func strength(for accent: AskContrast.RGB, isLight: Bool) -> Double {
        guard isLight else { return darkStrength }
        let gray = AskContrast.deemphasizedLight
        let line = AskContrast.over(gray.color, opacity: gray.opacity, .white)
        func holds(_ strength: Double) -> Bool {
            let lit = AskContrast.RGB(
                red: min(1, line.red + strength * accent.red),
                green: min(1, line.green + strength * accent.green),
                blue: min(1, line.blue + strength * accent.blue)
            )
            return AskContrast.ratio(lit, .white) >= AskGlassForeground.text
        }
        var hundredths = Int((darkStrength * 100).rounded())
        while hundredths > 0, !holds(Double(hundredths) / 100) {
            hundredths -= 1
        }
        return Double(hundredths) / 100
    }
}

#endif
