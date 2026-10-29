import Foundation

/// What confirming a proposal does.
///
/// **Additive by construction.** `AskProposal`'s decoder reads an absent kind
/// as `.perform`, so a proposal written without one reads back as what it
/// was, and a domain that only ever performs never names a kind.
nonisolated public enum AskProposalKind: String, Codable, Sendable {
    /// The app carries it out where it stands, in `AskDomain.perform(_:)`.
    case perform
    /// The app opens its own editor, seeded from the payload.
    ///
    /// **Nothing is saved by the tap.** The reader finishes in the editor, or
    /// cancels there, and neither outcome comes back, so the card says what it
    /// opened and never what it added. `perform` isn't called; opening the
    /// editor is the host's job, through the `askDraftOpener` it supplies, and
    /// a host that supplies none leaves the card's action disabled rather than
    /// offering a tap that does nothing. Not now still takes a tap.
    case handOff
}

/// Something an answer offers to do, which happens only if the reader says so.
///
/// **The model proposes, the reader confirms, the app performs.** A proposing
/// tool records one of these with `AskCollector.record(proposal:)` and returns
/// `modelReceipt`; it never acts itself. The answer carries the proposal out of
/// the turn, AskUI draws it as a card under the answer, and only the reader's
/// tap reaches `AskDomain.perform(_:)`.
///
/// **In the app's words.** The card is what the reader agrees to, so it says
/// what the app will do in the app's words, never in the model's words about
/// it. A proposing tool over the host's rows resolves the model's argument to
/// one of them first, records that row with `record(rows:)` as any lookup
/// does, and writes `title` and `detail` from the row. One with no row behind
/// it, such as a reminder, has only the model's reading of the request to
/// show: it shows what it will keep as it will keep it, clamped
/// (`AskPrompt.clamp`), inside the app's own words, so the reader confirms
/// the thing itself, not a description of it. `actionLabel` is the app's
/// alone, so the button the reader taps never says what the model wrote.
/// `title` and `detail` are drawn verbatim, never as Markdown.
///
/// **Only in a conversation.** A standalone turn (`AskTurnMode.standalone`:
/// Siri, a widget) has no card to confirm on, so a domain's `makeTools`
/// leaves a proposing tool out when `context.isConversation` is false, and
/// its `instructions` leave out any sentence naming it.
///
/// Behind no platform gate, like `AskAnswer`, which carries it into the
/// thread file.
nonisolated public struct AskProposal: Codable, Sendable, Equatable, Identifiable {
    /// The proposal's identity, kept with it in the thread file.
    public let id: UUID
    /// What confirming does: carry it out here, or open the app's own editor.
    public let kind: AskProposalKind
    /// What confirming does, in a few words: "Mark The Dispossessed as lent".
    public let title: String
    /// One line on what follows from it, when there is something to say.
    public let detail: String?
    /// The confirm button's label: "Mark as lent".
    public let actionLabel: String
    /// An SF Symbol beside the title.
    public let systemImage: String?
    /// What `perform` needs to carry it out, as JSON: AskKit encodes the
    /// value the initializer took, and `payload(as:)` reads it back. Empty
    /// for a proposal made without one. It rides into the thread file with
    /// its answer, so it is an identifier and an intent, never a copy of a
    /// row.
    public let payload: Data

    /// The most a proposal's payload may weigh: `AskCollector.record(proposal:)`
    /// refuses a heavier one. An id and a verb fit many times over.
    public static var maxPayloadBytes: Int { 4_096 }

    /// What a proposing tool returns to the model: nothing has happened yet,
    /// and the answer must not say otherwise. One sentence for every host, so
    /// no answer tells a reader something is done before they have said yes.
    public static var modelReceipt: String {
        "Proposed, not done: the reader confirms it on a card under your answer. Say what it would do; never say it is done."
    }

    /// What a **hand-off** tool returns instead. Sharper than `modelReceipt`
    /// because it has one more thing to deny: the reader has not tapped, so
    /// nothing is open either. An answer saying "I've opened the form" is as
    /// wrong as one saying "added".
    public static var handOffReceipt: String {
        "Proposed, not done: the reader confirms on a card under your answer, and confirming opens a form they fill in themselves. Say what it would start; never say it is done, and never say anything is open."
    }

    /// A proposal with each field as given and no payload, for one that
    /// `perform` can carry out from its title alone. Most are performed, so
    /// the kind defaults to `.perform`.
    public init(
        id: UUID = UUID(),
        kind: AskProposalKind = .perform,
        title: String,
        detail: String? = nil,
        actionLabel: String,
        systemImage: String? = nil
    ) {
        self.init(
            id: id, kind: kind, title: title, detail: detail, actionLabel: actionLabel, systemImage: systemImage,
            encodedPayload: Data()
        )
    }

    /// A proposal with each field as given, carrying `payload`, which AskKit
    /// encodes as JSON for `payload(as:)` to read back: the value itself,
    /// such as a row's id, never its encoding.
    ///
    /// **Throws, rather than proposing what can't be carried out.** A value
    /// that doesn't encode, such as a `Double` that is infinite or NaN, or a
    /// `Data`, which is a payload already encoded, throws the encoder's
    /// `EncodingError`: a mistake in the domain's type, which a card missing
    /// its payload, or an empty one, would hide until a reader confirmed it.
    public init(
        id: UUID = UUID(),
        kind: AskProposalKind = .perform,
        title: String,
        detail: String? = nil,
        actionLabel: String,
        systemImage: String? = nil,
        payload: some Encodable
    ) throws {
        self.init(
            id: id, kind: kind, title: title, detail: detail, actionLabel: actionLabel, systemImage: systemImage,
            encodedPayload: try AskPayloadCoding.encode(payload)
        )
    }

    /// A proposal whose payload is already JSON: what a test scripts.
    ///
    /// **Not public**, so a domain can't hand in bytes in an encoding of its
    /// own, which `payload(as:)` would read as nil.
    init(
        id: UUID = UUID(),
        kind: AskProposalKind = .perform,
        title: String,
        detail: String? = nil,
        actionLabel: String,
        systemImage: String? = nil,
        encodedPayload: Data
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.actionLabel = actionLabel
        self.systemImage = systemImage
        self.payload = encodedPayload
    }

    /// Hand-written, as `AskAnswer`'s is, so a field added later decodes a
    /// thread written before it existed: an absent `kind` reads as
    /// `.perform`, and an absent `payload` as empty.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decodeIfPresent(AskProposalKind.self, forKey: .kind) ?? .perform
        title = try container.decode(String.self, forKey: .title)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        actionLabel = try container.decode(String.self, forKey: .actionLabel)
        systemImage = try container.decodeIfPresent(String.self, forKey: .systemImage)
        payload = try container.decodeIfPresent(Data.self, forKey: .payload) ?? Data()
    }

    /// The payload as the domain's own type, decoded from the JSON AskKit
    /// encoded it as, or nil when there is none or it no longer decodes.
    public func payload<Value: Decodable>(as type: Value.Type) -> Value? {
        AskPayloadCoding.decode(type, from: payload)
    }
}

/// What became of a proposal, kept with the turn that made it.
nonisolated public enum AskProposalOutcome: Codable, Sendable, Equatable {
    /// The reader confirmed and the app carried it out. The line is the app's,
    /// returned by `AskDomain.perform(_:)`; nil reads "That's done".
    case confirmed(String?)
    /// The reader confirmed a `.handOff` and the app opened its editor. The
    /// line is the app's; nil reads a generic one.
    ///
    /// **Never "done".** What the reader does in the editor is theirs, and
    /// cancelling there isn't a failure, so this is a third outcome rather
    /// than `confirmed` with a softer line.
    case handedOff(String?)
    /// The reader said not now.
    case declined
    /// The reader confirmed and the app could not carry it out. The line is
    /// the one an `AskProposalFailure` carried; nil reads a generic line. The
    /// card offers the action again while its turn is the newest.
    case failed(String?)
    /// The reader confirmed, and nothing has said what came of it yet.
    /// Written to disk as the reader confirms, and the app is asked to carry
    /// it out only once that write has landed, so a chat that ends or an app
    /// that quits meanwhile never offers the action again: confirmed a second
    /// time, it could be done twice.
    ///
    /// AskUI replaces it with the outcome when `AskDomain.perform(_:)`
    /// returns, wherever the turn is by then: on screen, or filed with the
    /// earlier chats. Read back where nothing is carrying it out, as after an
    /// app quit before it returned, what came of it is unknown, and the card
    /// takes no tap. An outcome this build can't decode, such as a case a
    /// later AskKit wrote, reads back as this too.
    case performing
}

/// Thrown from `AskDomain.perform(_:)` when a proposal cannot be carried out,
/// with the line the card shows.
///
/// **The only error whose words reach the card.** Anything else thrown reads a
/// generic line: an arbitrary error's description is written for a log, not a
/// reader, and a Foundation Models error's can quote the reader's own data.
nonisolated public struct AskProposalFailure: Error, Equatable {
    /// The line the card shows, resolved against the app's own bundle. Nil
    /// reads the generic line.
    public let line: String?

    /// A failure that shows `line`, or the generic line when it is nil.
    public init(line: String? = nil) {
        self.line = line
    }
}
