#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import CoreGraphics
import Foundation
import FoundationModels
import Synchronization
import Testing

@testable import AskUI

/// The thumbnail above a question read back from disk is asked of the host off
/// the main actor, whatever the host's build settings (`AskQuestionThumbnail`).
@MainActor
@Suite(.timeLimit(.minutes(1))) struct AskQuestionThumbnailTests {
    /// A domain whose thumbnail read says where it ran. Its requirement is
    /// a plain `nonisolated async` one, in a target built with
    /// `NonisolatedNonsendingByDefault`, as a host's can be: it runs where it
    /// is called from.
    nonisolated struct ThumbnailDomain: AskDomain {
        let brand = AskBrand(
            title: "Ask Test", appDirectory: "AskKitUITests",
            logSubsystem: "AskKit.uitests", help: "help",
            firstScreenHeadline: "headline", firstScreenSentence: "sentence",
            disclosureSentence: "disclosure", scopeCaveat: "caveat"
        )
        /// Whether each read ran on the main thread, in order.
        let ranOnTheMainThread = ThumbnailLog()

        func makeTools(_ context: AskToolContext<AskNoRow>) -> [any Tool] { [] }
        func instructions(tier: AskTier, isConversation: Bool, answerLanguage: String?) -> String { "Answer." }

        func photoThumbnail(for photo: AskQuestionPhoto) async -> CGImage? {
            ranOnTheMainThread.record(pthread_main_np() != 0)
            return nil
        }
    }

    /// Where each thumbnail read ran. A class, because `Mutex` is
    /// non-Copyable and the domain is a struct.
    nonisolated final class ThumbnailLog: Sendable {
        private let reads = Mutex<[Bool]>([])

        func record(_ onMain: Bool) { reads.withLock { $0.append(onMain) } }
        var all: [Bool] { reads.withLock { $0 } }
    }

    /// **The loader the bubble awaits, awaited from the main actor as the
    /// bubble's task awaits it, reads off the main thread.** Called straight
    /// from there, as the row did, the host's read ran on the main actor, and
    /// a thread of photos read back from disk decoded each one there.
    @Test func theLoaderReadsTheHostsThumbnailOffTheMainThread() async {
        let domain = ThumbnailDomain()
        let load = AskQuestionThumbnail.loader(for: domain)
        _ = await load(AskQuestionPhoto(label: "Navy blazer", reference: "asset-1"))
        #expect(domain.ranOnTheMainThread.all == [false])
    }
}

#endif
