import Foundation

/// What the evidence line under one answer says: AskKit's count, the domain's
/// own words, or nothing (`AskDomain.evidence(for:)`).
///
/// **Only the words are the domain's.** Where there are rows behind the answer
/// (`AskAnswer.matches`) and the host draws them
/// (`AskScreen.evidenceDisclosure(_:)`), the line opens onto them whichever
/// words it reads; with none, it is plain text.
///
/// **An answer nothing grounded** (`AskGrounding.nothing`, which only a domain
/// whose policy is `AskGroundingPolicy.notRequired` records) reads "Not from
/// this app's data" under `.counted`, in place of a count. The domain's
/// `.line` and `.hidden` win over it. An answer with no grounding recorded (one
/// the domain gave without a model, a stopped turn, or one from a thread saved
/// before answers recorded it) is counted as any other: unknown is not a claim
/// that nothing grounded it.
///
/// Ungated, as `AskGroundingPolicy` is, so a host's shared code can name it on
/// every platform it builds for.
nonisolated public enum AskEvidencePresentation: Sendable, Equatable {
    /// AskKit's line: "From N items", with `AskDomain.evidenceScope(from:)`
    /// when it names one, and nothing when the answer has no rows behind it.
    /// The default.
    case counted
    /// No line, rows behind the answer or not, and so no way to open them.
    /// Not `none`, which a presentation held as an optional would read as
    /// nil.
    case hidden
    /// The domain's own line, resolved ("From 3 status pages, read just now"),
    /// drawn as it is. Resolve it against your own bundle, for the reason
    /// `AskDomain.phrase(for:)` gives. A line with no words draws nothing.
    case line(String)
}
