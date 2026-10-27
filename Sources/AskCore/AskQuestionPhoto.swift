import Foundation

/// The photo a question was asked with, as the thread keeps it: what it shows
/// and where the host can find it again, never its pixels.
///
/// **The label is the host's words for the picture.** The model is told it
/// with the image, and VoiceOver reads it for the thumbnail above the
/// question, so it names what the photo shows ("Blue record sleeve") rather than
/// passing a file name through.
///
/// **The reference is the host's own**, opaque to AskKit: an asset identifier,
/// a blob key. A thread read back from disk has no pixels, so the question's
/// thumbnail comes back through `AskDomain.photoThumbnail(for:)` with this in
/// hand. Nil for a photo the host keeps nowhere, whose restored question draws
/// a glyph in the thumbnail's place.
///
/// Behind no platform gate, and `nonisolated`, like everything
/// `AskThreadEntry` carries: the thread file is decoded off the main actor, on
/// every platform AskCore builds for. Without the `nonisolated`, the
/// package's main-actor default isolation would give this struct main-actor
/// `Codable` and `Equatable` conformances, which that decode can't use.
nonisolated public struct AskQuestionPhoto: Codable, Sendable, Equatable {
    /// What the photo shows, in the host's words. VoiceOver reads it for the
    /// thumbnail, and the model is told it with the image.
    public let label: String
    /// Where the host keeps the photo, in its own terms, or nil where it keeps
    /// it nowhere.
    public let reference: String?

    /// A photo with each field as given.
    public init(label: String, reference: String? = nil) {
        self.label = label
        self.reference = reference
    }
}
