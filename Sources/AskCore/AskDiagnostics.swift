import Foundation
public import Observation
import StoreKit

/// Whether this build may show developer rows.
///
/// **In AskCore, and behind no platform gate.** It is a fact about the
/// process, the same kind of thing `AskProcessEntitlements` is, not a view.
/// So a host's shared code can ask on every platform, and a host that runs
/// `AskEval` without the settings card can ask without importing AskUI.
/// StoreKit's `AppTransaction` is on all five platforms, tvOS and watchOS
/// included, so reading it needs no gate either.
///
/// **A runtime read, never `#if DEBUG` around the code it turns on.** A
/// TestFlight build is a Release build, and a signed build on a device is the
/// only place Private Cloud Compute can actually be measured, so the eval has
/// to be reachable there. `#if DEBUG` decides only `isDebugBuild`.
nonisolated public enum AskDiagnostics {
    /// A Debug build, or a TestFlight one, or a host that has turned the rows
    /// on for itself. It turns on the settings card's diagnostics rows
    /// (`AskPrivateCloudCard`, unless the host decides `showsDiagnostics`
    /// itself) and the thumbs under answers
    /// (`AskConversationStore.offersFeedback`).
    ///
    /// Main-actor because `enabledByApp` and `isTestFlight` are: a host flips
    /// the one at launch, StoreKit's answer sets the other, and the card reads
    /// both while drawing, which is the same actor every time. A view that
    /// reads it draws again when StoreKit's answer turns it on.
    @MainActor public static var isEnabled: Bool { isDebugBuild || isTestFlight || enabledByApp }

    /// Set by a host that carries its own diagnostics switch. AskKit reads no
    /// default for it: a package that invented a `UserDefaults` key would be
    /// reading one the host never wrote.
    @MainActor public static var enabledByApp = false

    /// Whether AskKit was compiled with `DEBUG` defined, as a Debug build of
    /// the host compiles it.
    public static let isDebugBuild: Bool = {
        #if DEBUG
        true
        #else
        false
        #endif
    }()

    /// Whether the App Store signed this app's transaction in its sandbox,
    /// which is how a TestFlight build reads: false until StoreKit has
    /// answered, and observable, so a view that reads it draws again when the
    /// answer turns it on.
    ///
    /// **Read from StoreKit's `AppTransaction.shared`, once a process, off
    /// the main actor.** The first read of this flag starts the read
    /// (`AskTestFlightReading`), and the flag is set on the main actor when it
    /// lands. The read can take the network on a first launch, so nothing on
    /// the main actor waits for it, and a launch that can't get an answer
    /// reads false until the next. A transaction StoreKit couldn't verify
    /// reads false too: the flag turns on developer rows, and a forged
    /// environment shouldn't. A Debug build never asks, since it shows the
    /// rows whatever the answer, and so neither does `swift test`.
    ///
    /// What `AppTransaction.environment` says, by build, from Apple's StoreKit
    /// documentation and the 27.2 SDK's interfaces (none of it measured here):
    /// - **TestFlight**: `.sandbox`, on every platform, the Mac's included
    ///   ("Apps that you download from TestFlight always run in the sandbox
    ///   environment"). The receipt file this used to look for is somewhere
    ///   else on the Mac, so a Mac TestFlight build read false before.
    /// - **A development-signed build run from Xcode**: `.sandbox` too, or
    ///   `.xcode` under a StoreKit configuration file, which reads false. A
    ///   Release build run that way reads true; a Debug one never asks.
    /// - **App Review**: the documentation names no environment of its own.
    ///   A build under review buys in the sandbox, so it most likely reads
    ///   `.sandbox`, and true, as the receipt check most likely did too.
    /// - **The App Store**: `.production`, false.
    ///
    /// **Nothing public in 27.2 tells TestFlight from App Review on every
    /// platform.** `AppStore.Environment` has only `.production`, `.sandbox`
    /// and `.xcode`. MarketplaceKit's `AppDistributor.current` has a
    /// `.testFlight` case, but on iOS alone, and says nothing of review
    /// builds; MetricKit's `isTestFlightApp` arrives only inside a payload
    /// MetricKit delivers, and not on tvOS or watchOS. A host that must keep
    /// the rows from a reviewer passes `showsDiagnostics` to
    /// `AskPrivateCloudCard` itself.
    @MainActor public static var isTestFlight: Bool { testFlightReading.isTestFlight }

    /// The process's one read of its app transaction, started by the first
    /// read of `isTestFlight`, unless this is a Debug build.
    @MainActor static let testFlightReading: AskTestFlightReading = {
        let reading = AskTestFlightReading()
        if !isDebugBuild {
            Task { await reading.read { await AskTestFlightReading.appTransactionEnvironment() } }
        }
        return reading
    }()
}

/// Whether StoreKit says this app was signed in the App Store's sandbox: the
/// flag `AskDiagnostics.isTestFlight` reads, and the one read that sets it.
///
/// **An object, not a static.** `AskDiagnostics` holds the process's one, so
/// a view reading the flag through it is told when it changes, and a test
/// makes its own and reads it with a fake StoreKit, leaving the process's
/// alone.
@MainActor
@Observable
final class AskTestFlightReading {
    /// Whether the read found the sandbox: false until it lands.
    private(set) var isTestFlight = false

    /// Reads `environment` and sets the flag from it, on the main actor.
    ///
    /// - Parameter environment: The environment the App Store signed the
    ///   app's transaction in, or nil where there is none to read. The
    ///   process's read is `appTransactionEnvironment()`, which runs off the
    ///   main actor.
    func read(_ environment: () async -> AppStore.Environment?) async {
        isTestFlight = Self.readsAsTestFlight(await environment())
    }

    /// Whether an environment is a TestFlight build's: the sandbox, and
    /// nothing else. The Xcode environment is a StoreKit configuration file's,
    /// a development run's, and nil is no answer.
    nonisolated static func readsAsTestFlight(_ environment: AppStore.Environment?) -> Bool {
        environment == .sandbox
    }

    /// The environment of the app's verified transaction, or nil where
    /// StoreKit has none, couldn't verify it, or threw. Off the main actor:
    /// it can wait on the network.
    ///
    /// `AppTransaction.shared`, never `refresh()`: the refresh asks the App
    /// Store's server and can put a sign-in in front of the reader.
    @concurrent
    nonisolated static func appTransactionEnvironment() async -> AppStore.Environment? {
        guard case .verified(let transaction) = try? await AppTransaction.shared else { return nil }
        return transaction.environment
    }
}
