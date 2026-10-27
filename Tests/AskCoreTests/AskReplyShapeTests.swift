#if canImport(FoundationModels) && !os(tvOS)

import Foundation
import FoundationModels
import Synchronization
import Testing

@testable import AskCore

/// The two reply shapes as the model is sent them, and the sessions that
/// stream them.
@Suite(.timeLimit(.minutes(1))) @MainActor struct AskReplyShapeTests {

    /// A schema as the model is sent it, as JSON objects.
    private static func encoded(_ schema: GenerationSchema) throws -> [String: Any] {
        let data = try JSONEncoder().encode(schema)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static func property(_ name: String, of schema: [String: Any]) throws -> NSDictionary {
        let properties = try #require(schema["properties"] as? [String: Any])
        return NSDictionary(dictionary: try #require(properties[name] as? [String: Any]))
    }

    /// **The prose reply's two fields are the full reply's, word for word**:
    /// the same guides, and the follow-ups' count of two. Both read one text
    /// (`AskReply.answerGuide`, `AskReply.followUpsGuide`), so a guide written
    /// out again in one shape, and reworded there, fails here, as does a field
    /// added to the prose reply or an order changed.
    @Test func theProseReplysFieldsAreTheFullReplysWordForWord() throws {
        let full = try Self.encoded(AskReply.generationSchema)
        let prose = try Self.encoded(AskProseReply.generationSchema)
        #expect(try Self.property("answer", of: prose) == Self.property("answer", of: full))
        #expect(try Self.property("followUps", of: prose) == Self.property("followUps", of: full))
        #expect(prose["x-order"] as? [String] == ["answer", "followUps"])
        #expect(prose["required"] as? [String] == ["answer", "followUps"])
    }

    /// The full reply keeps its five fields in their load-bearing order.
    @Test func theFullReplyKeepsItsFieldsInOrder() throws {
        let full = try Self.encoded(AskReply.generationSchema)
        #expect(full["x-order"] as? [String] == ["answer", "questionKind", "showsEveryMatch", "tiles", "followUps"])
    }

    /// A session written before reply shapes streams its full reply for
    /// either shape, and refuses a photo as it always has.
    @Test func theDefaultStreamsTheFullReplyWhateverTheShape() async throws {
        for shape in [AskReplyShape.full, .prose] {
            var snapshots: [AskReplySnapshot] = []
            for try await snapshot in WordsOnlySession().stream(
                prompt: "q", images: [], temperature: 0.4, reasoningLevel: nil,
                includeSchemaInPrompt: true, shape: shape
            ) {
                snapshots.append(snapshot)
            }
            #expect(snapshots.map(\.answer) == ["Words."])
        }
        await #expect(throws: AskError.photosNotSupported) {
            for try await _ in WordsOnlySession().stream(
                prompt: "q", images: [testPhoto()], temperature: 0.4, reasoningLevel: nil,
                includeSchemaInPrompt: true, shape: .prose
            ) {}
        }
    }

    /// A refine pass's session passes the shape it was asked for on to the
    /// turn's session, behind the generation gate.
    @Test func theGatedSessionPassesTheShapeOn() async throws {
        let base = FakeSession(FakeSession.Script(snapshots: [.answering("Words.", kind: AskQuestionKind.pick)]))
        let seam = FakeSeam(status: AskModelStatus())
        let gated = AskGatedSession(base: base, seam: seam, onDevice: true) {}
        var snapshots: [AskReplySnapshot] = []
        for try await snapshot in gated.stream(
            prompt: "q", images: [], temperature: 0.4, reasoningLevel: nil,
            includeSchemaInPrompt: false, shape: .prose
        ) {
            snapshots.append(snapshot)
        }
        #expect(base.shapes.withLock { $0 } == [.prose])
        #expect(snapshots == [AskReplySnapshot(answer: "Words.")])
        #expect(seam.generationsGated.withLock { $0 } == 1)
    }
}

#endif
