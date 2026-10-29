import Foundation

/// AskKit's one encoding for a payload, a turn's and a proposal's: JSON, as a
/// default `JSONEncoder` writes it and a default `JSONDecoder` reads it.
///
/// **One encoding in and out, so what goes in comes back.** A domain hands
/// AskKit its value, never bytes: a turn's payload through
/// `AskCollector.record(payload:)` or `mergePayload(as:_:)`, a proposal's
/// through `AskProposal`'s initializer. Each is encoded here, and read back
/// here by `AskAnswer.payload(as:)` and `AskProposal.payload(as:)`, so a
/// payload in an encoding of the domain's own, which those would read as nil
/// and leave its card out without a word, can't go in.
///
/// **Defaults, on purpose.** No output formatting and no strategies: the bytes
/// for a value are what `JSONEncoder()` writes for it, as they are in the chat
/// files AskKit 0.2.0's domains wrote, so those payloads still read back.
nonisolated enum AskPayloadCoding {
    /// `value` as JSON.
    ///
    /// Throws the encoder's `EncodingError` for a value JSON can't hold, such
    /// as a `Double` that is infinite or NaN, and for a `Data`. A `Data` is a
    /// payload already encoded, and encoded again it would be a base64 string
    /// that reads back as nothing but `Data`: the silent nil this type is here
    /// to prevent, by another route.
    static func encode(_ value: some Encodable) throws -> Data {
        if value is Data {
            throw EncodingError.invalidValue(value, EncodingError.Context(
                codingPath: [],
                debugDescription: "A payload is the value itself, not its encoding: AskKit encodes it as JSON."
            ))
        }
        return try JSONEncoder().encode(value)
    }

    /// `data` decoded as `type`, or nil when it doesn't decode as one.
    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) -> Value? {
        try? JSONDecoder().decode(type, from: data)
    }
}
