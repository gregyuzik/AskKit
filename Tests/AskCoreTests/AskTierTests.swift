import Foundation
import Testing

@testable import AskCore

/// `AskTier` is persisted inside `ask-thread.json`, so its raw values are a
/// storage contract, not an implementation detail. This pins them.
@Suite(.timeLimit(.minutes(1))) struct AskTierTests {
    @Test func rawValuesAreTheStorageContract() {
        #expect(AskTier.privateCloud.rawValue == "privateCloud")
        #expect(AskTier.onDevice.rawValue == "onDevice")
        #expect(AskTier.allCases.count == 2)
    }

    @Test func roundTripsThroughJSON() throws {
        for tier in AskTier.allCases {
            let data = try JSONEncoder().encode(tier)
            #expect(try JSONDecoder().decode(AskTier.self, from: data) == tier)
        }
    }

    @Test func onlyPrivateCloudComputeReadsPhotos() {
        #expect(AskTier.privateCloud.readsPhotos)
        #expect(!AskTier.onDevice.readsPhotos)
    }
}
