import AskCore
import Foundation
import Testing

#if os(iOS) || os(macOS) || os(visionOS)
import AskUI
#endif

#if canImport(FoundationModels) && !os(tvOS)
import FoundationModels
#endif

/// A request the model can't take, whether this is a TestFlight build, and
/// the settings card's state, as a host without the posture reaches them.
@Suite(.timeLimit(.minutes(1))) struct CrossPostureErrorAndTestFlightTests {

    /// The failure, its line and its stored form, read off any actor as a
    /// host's own screen, Siri intent or archive reads them, and named in a
    /// host's own switch, which ends in `@unknown default` since `AskError`
    /// is open.
    @Test func aRequestTheModelCantTakeIsReadWithoutThePosture() throws {
        let error = AskError.requestNotSupported
        #expect(!error.isRetryable)
        #expect(error.errorDescription?.isEmpty == false)
        let encoded = try JSONEncoder().encode(error)
        #expect(try JSONDecoder().decode(AskError.self, from: encoded) == .requestNotSupported)
        let offersTryAgain = switch error {
        case .modelUnavailable, .refused, .contextTooLarge, .photosNotSupported, .requestNotSupported: false
        case .couldNotAnswer, .ungrounded, .privateCloudUnreachable, .quotaReached, .model, .stopped: true
        @unknown default: error.isRetryable
        }
        #expect(offersTryAgain == error.isRetryable)
    }

    #if canImport(FoundationModels) && !os(tvOS)
    /// What a host triaging its own sessions' failures gets, off any actor,
    /// for a guide its model doesn't support and for a model that can't see.
    @Test func aHostsOwnTriageReadsWhatTheModelCantTake() {
        let guide = LanguageModelError.unsupportedGenerationGuide(.init(schemaName: nil, debugDescription: "guide"))
        #expect(AskTriage.askError(from: guide, tier: .privateCloud) == .requestNotSupported)
        let vision = LanguageModelError.unsupportedCapability(.init(capability: .vision, debugDescription: "vision"))
        #expect(AskTriage.askError(from: vision, tier: .onDevice) == .photosNotSupported)
    }
    #endif

    /// Whether this is a TestFlight build, read on the main actor, where
    /// StoreKit's answer is set, beside the switch it feeds.
    @MainActor
    @Test func whetherThisIsATestFlightBuildIsReadOnTheMainActor() {
        let flight = AskDiagnostics.isTestFlight
        #expect(AskDiagnostics.isEnabled == (AskDiagnostics.isDebugBuild || flight || AskDiagnostics.enabledByApp))
    }

    #if os(iOS) || os(macOS) || os(visionOS)
    /// A host's own settings row reads the card's state on the main actor,
    /// and reads nothing from a mirror its seam hasn't published to.
    @MainActor
    @Test func aHostsSettingsRowReadsNoStateBeforeTheSeamHasPublished() {
        let state: AskPrivateCloudState? = AskPrivateCloudState.of(AskModelStatus())
        #expect(state == nil)
    }
    #endif
}
