import Foundation
import Testing

@testable import AskCore

/// The development park: which builds keep off Private Cloud Compute.
///
/// A table rather than a sample, because every parked row is a way a
/// development run would spend the developer's own daily quota unparked: a UI
/// test that opens the Ask screen, a Release build run in a simulator, a
/// Profile run on a device. Only the shipped build, from TestFlight or the
/// App Store, reaches Private Cloud Compute unasked.
@Suite(.timeLimit(.minutes(1))) struct AskDevelopmentParkTests {

    private func reason(
        debug: Bool = false, simulator: Bool = false, developmentSigned: Bool = false,
        processName: String = "AskKitDemo",
        environment: [String: String] = [:], launchArguments: [String: Any] = [:],
        appOptIn: Bool = false
    ) -> String? {
        AskDevelopmentPark.reason(
            isDebugBuild: debug, isSimulator: simulator, isDevelopmentSigned: developmentSigned,
            processName: processName,
            environment: environment, launchArguments: launchArguments, appOptIn: appOptIn
        )
    }

    @Test func theShippedBuildIsNeverParked() {
        // Release, on a device, signed for distribution, no test runner: what
        // every reader runs. Parking it would take Ask's better model away from
        // everyone, which is the one thing this must never do.
        #expect(reason() == nil)
    }

    @Test func everyDevelopmentBuildIsParked() {
        #expect(reason(debug: true) == "Debug build")
        // A simulator build can be Release, so the configuration alone is not
        // enough: a simulator is parked in every configuration.
        #expect(reason(simulator: true) == "simulator")
        // A Profile run, or a Release build a developer installs by hand: the
        // binary carries `get-task-allow`, which no distribution build does.
        #expect(reason(developmentSigned: true) == "development-signed")
    }

    @Test func aTestHostIsParkedInAnyConfiguration() {
        // A test run can be built Release, so the runner's own keys decide it.
        for key in ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"] {
            #expect(reason(environment: [key: "/x"]) == "test host", "\(key)")
        }
    }

    @Test func aSwiftTestRunnerIsParkedInAnyConfiguration() {
        // `swift test` runs Swift Testing in `swiftpm-testing-helper` and
        // XCTest in `xctest`, and neither sets XCTest's keys: without its name,
        // a `swift test` run would be parked only for how it happened to be
        // built.
        for runner in ["swiftpm-testing-helper", "xctest"] {
            #expect(reason(processName: runner) == "swift test runner", "\(runner)")
            #expect(reason(processName: runner, environment: [AskDevelopmentPark.optInKey: "1"]) == nil, "\(runner)")
        }
        // By its whole name: an app is never parked for what it is called.
        for app in ["AskKitDemo", "ExampleApp", "example", "Library", "xctest-app", "Xctest"] {
            #expect(reason(processName: app) == nil, "\(app)")
        }
    }

    @Test func theOptInLiftsEveryPark() {
        let parked: [(Bool, Bool, Bool, [String: String])] = [
            (true, false, false, [:]),
            (false, true, false, [:]),
            (false, false, true, [:]),
            (false, false, false, ["XCTestSessionIdentifier": "x"])
        ]
        for (debug, simulator, signed, environment) in parked {
            var optedIn = environment
            optedIn[AskDevelopmentPark.optInKey] = "1"
            #expect(reason(debug: debug, simulator: simulator, developmentSigned: signed,
                           environment: optedIn) == nil)
            #expect(reason(debug: debug, simulator: simulator, developmentSigned: signed,
                           environment: environment,
                           launchArguments: [AskDevelopmentPark.optInKey: "YES"]) == nil)
            #expect(reason(debug: debug, simulator: simulator, developmentSigned: signed,
                           environment: environment, appOptIn: true) == nil)
        }
    }

    @Test func onlyAYesOptsIn() {
        // `ASK_LIVE_PCC=0` is somebody turning it off, not on.
        for value in ["0", "", "no", "false"] {
            #expect(reason(debug: true, environment: [AskDevelopmentPark.optInKey: value]) != nil, "\(value)")
            #expect(reason(debug: true, launchArguments: [AskDevelopmentPark.optInKey: value]) != nil, "\(value)")
        }
        for value in ["1", "YES", "yes", "true", "TRUE"] {
            #expect(reason(debug: true, environment: [AskDevelopmentPark.optInKey: value]) == nil, "\(value)")
        }
        #expect(reason(debug: true, launchArguments: [AskDevelopmentPark.optInKey: true]) == nil)
        #expect(reason(debug: true, launchArguments: [AskDevelopmentPark.optInKey: 1]) == nil)
    }

    @Test func theLaunchArgumentIsReadFromTheArgumentDomainAlone() {
        // `UserDefaults.standard` also holds whatever an earlier run
        // persisted, so a flag left in a simulator's defaults would unpark
        // every later run on it. The argument domain is only what this launch
        // was given, so `launchArgumentOptIn` takes that dictionary and
        // nothing wider.
        #expect(AskDevelopmentPark.launchArgumentOptIn(argumentDomain: [:]) == false)
        #expect(AskDevelopmentPark.launchArgumentOptIn(argumentDomain: nil) == false)
        #expect(AskDevelopmentPark.launchArgumentOptIn(
            argumentDomain: [AskDevelopmentPark.optInKey: "1"]
        ))
    }

    /// Whether whoever ran these tests opted the run in
    /// (`ASK_LIVE_PCC=1 swift test`): this process's environment and launch
    /// arguments, read through the park's own rule. Nothing but the opt-in
    /// unparks a Debug build.
    private var thisRunOptedIn: Bool {
        reason(
            debug: true,
            environment: ProcessInfo.processInfo.environment,
            launchArguments: UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        ) == nil
    }

    @Test func thisTestProcessIsParkedUnlessTheRunOptedIn() {
        // `swift test` runs a Debug build under a test runner: parked twice
        // over, and the reason a test here can never spend a request. An
        // exported opt-in lifts that for this process as for any other, and a
        // developer measuring Private Cloud Compute is doing it on purpose.
        #expect(AskDevelopmentPark.isParked == !thisRunOptedIn)
        #expect((AskDevelopmentPark.reason == nil) == thisRunOptedIn)
    }

    @Test func thisTestProcessIsParkedForBeingATest() {
        // For being a test, not only for being a Debug build, so that
        // `swift test -c release` is parked as well: in a `swift test` runner
        // by its name, or in an Xcode test host by XCTest's keys.
        //
        // This process's name and environment, with the opt-in taken out and
        // nothing else counted: an exported `ASK_LIVE_PCC` unparks the run,
        // and says nothing about what the runner is.
        var environment = ProcessInfo.processInfo.environment
        environment[AskDevelopmentPark.optInKey] = nil
        let parkedAs = reason(processName: ProcessInfo.processInfo.processName, environment: environment)
        #expect(parkedAs == "swift test runner" || parkedAs == "test host",
                "\(ProcessInfo.processInfo.processName) was parked as \(parkedAs ?? "nothing")")
    }
}
