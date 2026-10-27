import Foundation
import Synchronization

/// Whether this process keeps off Private Cloud Compute because it is a
/// development build, not the one readers run.
///
/// **The daily quota is per iCloud account, and a developer's account is the
/// one every development run spends.** Unparked, UI tests that open the Ask
/// screen, simulator builds and Profile runs each warm or ask on Private
/// Cloud Compute, and a morning of them was measured spending a whole day's
/// quota. `AppleModelSeam` reads this one park, so every host is parked the
/// same way.
///
/// Parked: a test host or a `swift test` runner in any configuration, a Debug
/// build, a simulator in any configuration, and a development-signed build
/// (`get-task-allow`: a Profile run, or a Release build installed by hand).
/// TestFlight and App Store builds are never parked. A parked process sends
/// Private Cloud Compute nothing at all: no session, no prewarm, no locale
/// probe, no context-size read. The tier reads `.notEntitled`, which the
/// settings card words as "isn't enabled in this build".
///
/// `ASK_LIVE_PCC=1` in the environment, or `-ASK_LIVE_PCC YES` as a launch
/// argument, opts a development run back in: the way to measure Private Cloud
/// Compute from a signed build. A host can pass its own flag with
/// `setAppOptIn(_:)`.
///
/// Behind no platform gate, like `AskProcessEntitlements`: the answer is a
/// fact about the build, and a tvOS or watchOS host asking it needs no
/// framework.
nonisolated public enum AskDevelopmentPark {
    /// The opt-in's name, as an environment variable or a launch argument.
    public static let optInKey = "ASK_LIVE_PCC"

    /// Why this process is parked ("Debug build", "simulator", "test host",
    /// "swift test runner" or "development-signed"), or nil when it may reach
    /// Private Cloud Compute. For a log line or a diagnostics row; `isParked`
    /// is the question.
    ///
    /// Only the host's opt-in is read on each use, because it can be a switch.
    /// The build, the signature, the process's name, the environment and the
    /// launch arguments can't change under a process, and are read once.
    public static var reason: String? {
        appOptIn.withLock { $0 }() ? nil : buildReason
    }

    /// Whether this process keeps off Private Cloud Compute right now.
    public static var isParked: Bool { reason != nil }

    private static let buildReason: String? = reason(
        isDebugBuild: isDebugBuild,
        isSimulator: isSimulator,
        isDevelopmentSigned: AskProcessEntitlements.isDevelopmentSigned,
        processName: ProcessInfo.processInfo.processName,
        environment: ProcessInfo.processInfo.environment,
        launchArguments: UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain),
        appOptIn: false
    )

    /// Let a host's own development flag, such as an environment variable of
    /// its own, lift the park beside `ASK_LIVE_PCC`. The closure is asked on
    /// every read of `reason`, so it can be a switch.
    ///
    /// **An explicit opt-in, never the host's own park answer.** A host whose
    /// park doesn't know about development signing would, by passing "not
    /// parked", unpark every Profile run this one parks.
    public static func setAppOptIn(_ optIn: @escaping @Sendable () -> Bool) {
        appOptIn.withLock { $0 = optIn }
    }

    private static let appOptIn = Mutex<@Sendable () -> Bool>({ false })

    /// The processes `swift test` runs tests in: `swiftpm-testing-helper` for
    /// Swift Testing and `xctest` for XCTest. Neither sets XCTest's
    /// environment keys, which are how an Xcode test host is known, so a
    /// `swift test` run is known by its runner's name. Without it, such a run
    /// would be parked only by how it happened to be built and signed, not
    /// because it is a test run.
    static let swiftTestRunners: Set<String> = ["swiftpm-testing-helper", "xctest"]

    /// The decision, as a pure function of what it reads, so its table is
    /// testable. The opt-in wins; then a test host or a `swift test` runner in
    /// any configuration, because a test run can be built Release; then a
    /// Debug build; then a simulator in any configuration; then a
    /// development-signed binary.
    static func reason(
        isDebugBuild: Bool,
        isSimulator: Bool,
        isDevelopmentSigned: Bool,
        processName: String,
        environment: [String: String],
        launchArguments: [String: Any]?,
        appOptIn: Bool
    ) -> String? {
        if appOptIn || isYes(environment[optInKey]) || launchArgumentOptIn(argumentDomain: launchArguments) {
            return nil
        }
        let testHostKeys = ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"]
        if testHostKeys.contains(where: { environment[$0] != nil }) { return "test host" }
        if swiftTestRunners.contains(processName) { return "swift test runner" }
        if isDebugBuild { return "Debug build" }
        if isSimulator { return "simulator" }
        if isDevelopmentSigned { return "development-signed" }
        return nil
    }

    /// The launch argument, read from the argument domain alone, which holds
    /// only what this launch was given.
    ///
    /// Why not `UserDefaults.standard.bool(forKey:)`: ARCHITECTURE.md,
    /// Rejected designs.
    static func launchArgumentOptIn(argumentDomain: [String: Any]?) -> Bool {
        switch argumentDomain?[optInKey] {
        case let value as Bool: value
        case let value as NSNumber: value.boolValue
        case let value as String: isYes(value)
        default: false
        }
    }

    private static func isYes(_ value: String?) -> Bool {
        guard let value else { return false }
        return ["1", "yes", "true"].contains(value.lowercased())
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
}
