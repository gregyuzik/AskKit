import Foundation
import Observation
import StoreKit
import Testing

@testable import AskCore

/// Whether this is a TestFlight build, as StoreKit's app transaction says
/// (`AskDiagnostics.isTestFlight`).
///
/// Each test reads with an `AskTestFlightReading` of its own and a fake
/// StoreKit, so the process's flag is left alone, and nothing here asks the
/// App Store anything.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct AskTestFlightReadingTests {

    /// TestFlight signs in the sandbox, on every platform, the Mac's
    /// included, where the receipt file AskKit used to look for isn't. The
    /// App Store signs in production, and a StoreKit configuration file in
    /// Xcode's environment.
    @Test func onlyTheSandboxReadsAsTestFlight() {
        #expect(AskTestFlightReading.readsAsTestFlight(.sandbox))
        #expect(!AskTestFlightReading.readsAsTestFlight(.production))
        #expect(!AskTestFlightReading.readsAsTestFlight(.xcode))
        #expect(!AskTestFlightReading.readsAsTestFlight(AppStore.Environment(rawValue: "LocalTesting")))
        // No answer: no transaction, one StoreKit couldn't verify, or a throw.
        #expect(!AskTestFlightReading.readsAsTestFlight(nil))
    }

    @Test func theFlagIsFalseUntilTheReadLands() async {
        let reading = AskTestFlightReading()
        #expect(!reading.isTestFlight)
        await reading.read { .sandbox }
        #expect(reading.isTestFlight)
    }

    @Test func anAppStoreBuildOrNoAnswerLeavesItOff() async {
        let production = AskTestFlightReading()
        await production.read { .production }
        #expect(!production.isTestFlight)
        let unanswered = AskTestFlightReading()
        await unanswered.read { nil }
        #expect(!unanswered.isTestFlight)
    }

    /// **The flag is observable**, so a view that read it, as the settings
    /// card reads `AskDiagnostics.isEnabled` while drawing, is told when the
    /// read lands after launch and turns the rows on.
    @Test func aViewThatReadTheFlagIsToldWhenTheReadLands() async {
        let reading = AskTestFlightReading()
        let (changed, signal) = AsyncStream<Void>.makeStream()
        withObservationTracking {
            _ = reading.isTestFlight
        } onChange: {
            signal.yield()
        }
        await reading.read { .sandbox }
        var heard = changed.makeAsyncIterator()
        #expect(await heard.next() != nil)
    }

    /// The switch is the three of them: a Debug build, a TestFlight one, or
    /// the host's own word. `swift test` is a Debug build, which never asks
    /// StoreKit, so the process's flag is still off here.
    @Test func theSwitchIsADebugBuildATestFlightOneOrTheHostsWord() {
        #expect(AskDiagnostics.isDebugBuild)
        #expect(!AskDiagnostics.isTestFlight)
        #expect(AskDiagnostics.isEnabled == (AskDiagnostics.isDebugBuild || AskDiagnostics.isTestFlight || AskDiagnostics.enabledByApp))
    }
}
