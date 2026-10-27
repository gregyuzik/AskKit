import Foundation
import Testing

@testable import AskCore

/// The entitlement read, such as it is.
///
/// The simulator branch — the sole guard behind "an unentitled request is fatal
/// in a simulator app" — is compiled by the push gate's simulator builds and
/// run by no automated test: `swift test` runs on macOS, and the UI bundle
/// that would exercise it is built and deliberately never run by the push
/// gate (`scripts/ui-smoke.sh` runs it by hand). What can be pinned from a
/// host test is that asking is safe, which is the property a trap would
/// break.
@Suite(.timeLimit(.minutes(1))) struct AskProcessEntitlementsTests {

    @Test func askingForAnEntitlementNothingHoldsReadsItAbsentRatherThanTrapping() {
        // On macOS this really reads `SecTask`; in a simulator build it parses
        // a Mach-O section; on a device it reads the provisioning profile, and
        // a hand-signed build's profile does not grant a key nobody has ever
        // requested. Either way it must answer, not crash — a malformed read
        // in any of the three would take the app down at launch.
        let reading = AskProcessEntitlements.reading("com.apple.developer.no-such-entitlement-exists")
        #expect(reading != .present)
        #if os(macOS) || targetEnvironment(simulator)
        // macOS and a simulator read exactly: nothing here is left to a
        // declaration.
        #expect(reading == .absent)
        #endif
    }

    // MARK: - The host's declaration, weighed against the reading

    @Test func noProfileAndUndeclaredIsNotEntitled() {
        // Every TestFlight and App Store build: distribution strips the
        // profile, so nothing on the device can be read, and a host that did
        // not declare the entitlement must never reach a request. Read as a
        // yes, the missing profile traps this build with "Missing
        // entitlement" on its first online question.
        let reading = AskProcessEntitlements.reading(AskProcessEntitlements.privateCloudCompute, inProfile: nil)
        #expect(reading == .unreadable)
        #expect(AskProcessEntitlements.privateCloudComputeRefusal(.undeclared, reading: reading) != nil)
    }

    @Test func noProfileAndDeclaredIsEntitled() {
        // The same shipped build, from a host that declared the entitlement:
        // the declaration is all there is to go on, and it is trusted.
        let reading = AskProcessEntitlements.reading(AskProcessEntitlements.privateCloudCompute, inProfile: nil)
        #expect(AskProcessEntitlements.privateCloudComputeRefusal(.declared, reading: reading) == nil)
    }

    @Test func aProfileWithoutTheKeyIsNotEntitledWhateverTheHostDeclares() {
        // A development build signed with a team profile that grants nothing
        // but the defaults: the profile is the upper bound of what the binary
        // can hold, so a declaration can't put the key back.
        let granted = AskProcessEntitlements.entitlements(
            inProvisioningProfile: profile(granting: [
                "application-identifier", "com.apple.developer.team-identifier", "get-task-allow"
            ])
        )
        let reading = AskProcessEntitlements.reading(AskProcessEntitlements.privateCloudCompute, inProfile: granted)
        #expect(reading == .absent)
        #expect(AskProcessEntitlements.privateCloudComputeRefusal(.declared, reading: reading) != nil)
        #expect(AskProcessEntitlements.privateCloudComputeRefusal(.undeclared, reading: reading) != nil)
    }

    @Test func aProfileThatGrantsTheKeyLeavesItToTheDeclaration() {
        // A grant is an upper bound, not proof the binary claims the key, so
        // the host still has to say it does.
        let granted = AskProcessEntitlements.entitlements(
            inProvisioningProfile: profile(granting: [
                "application-identifier", AskProcessEntitlements.privateCloudCompute
            ])
        )
        let reading = AskProcessEntitlements.reading(AskProcessEntitlements.privateCloudCompute, inProfile: granted)
        #expect(reading == .present)
        #expect(AskProcessEntitlements.privateCloudComputeRefusal(.declared, reading: reading) == nil)
        #expect(AskProcessEntitlements.privateCloudComputeRefusal(.undeclared, reading: reading) != nil)
    }

    @Test func theExactReadWinsOnTheMacAndInTheSimulator() {
        // What the Mac's `SecTask` and a simulator build's embedded section
        // read is the binary's own signature, so it outranks a declaration
        // either way it disagrees — and an undeclared tier stays off even in
        // a build that carries the key.
        #expect(AskProcessEntitlements.privateCloudComputeRefusal(.declared, reading: .absent) != nil)
        #expect(AskProcessEntitlements.privateCloudComputeRefusal(.declared, reading: .present) == nil)
        #expect(AskProcessEntitlements.privateCloudComputeRefusal(.undeclared, reading: .present) != nil)
        #if os(macOS) || targetEnvironment(simulator)
        // The runner these tests run in carries no Private Cloud Compute
        // entitlement, and says so exactly: declaring it changes nothing.
        let live = AskProcessEntitlements.privateCloudComputeReading
        #expect(live == .absent)
        #expect(AskProcessEntitlements.privateCloudComputeRefusal(.declared, reading: live) != nil)
        #endif
    }

    // MARK: - The provisioning profile, which is the device's only reading

    /// A profile-shaped blob: the plist Apple carries inside a CMS signature,
    /// with bytes either side of it that are not plist and must be skipped.
    private func profile(granting keys: [String]) -> Data {
        let entitlements = keys.map { "<key>\($0)</key><true/>" }.joined()
        let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict>
            <key>Name</key><string>iOS Team Provisioning Profile: *</string>
            <key>Entitlements</key><dict>\(entitlements)</dict>
            </dict></plist>
            """
        var data = Data([0x30, 0x82, 0x0A, 0xBC, 0x06, 0x09, 0x2A])
        data.append(Data(plist.utf8))
        data.append(Data([0x31, 0x82, 0x03, 0x1F]))
        return data
    }

    @Test func theProfilesGrantsAreReadOutOfItsSignature() {
        let granted = AskProcessEntitlements.entitlements(
            inProvisioningProfile: profile(granting: [
                "application-identifier", AskProcessEntitlements.privateCloudCompute
            ])
        )
        #expect(granted?[AskProcessEntitlements.privateCloudCompute] != nil)
        #expect(granted?["com.apple.developer.healthkit"] == nil)
    }

    @Test func aDefaultTeamProfileReadsAsNotGrantingTheKey() {
        // **The measurement this read exists for.** An iPhone 17 Pro, a
        // development build of the demo, first turn:
        //
        //     Fatal error: Missing entitlement:
        //     com.apple.developer.private-cloud-compute
        //     App terminated due to signal 5.
        //
        // Its profile is the default team one — `application-identifier`,
        // `team-identifier`, `get-task-allow`, `keychain-access-groups` and
        // nothing else — so the absence is readable, and reading it is the
        // difference between handing down to on-device and a trap.
        let granted = AskProcessEntitlements.entitlements(
            inProvisioningProfile: profile(granting: [
                "application-identifier", "com.apple.developer.team-identifier",
                "get-task-allow", "keychain-access-groups"
            ])
        )
        #expect(granted != nil)
        #expect(granted?[AskProcessEntitlements.privateCloudCompute] == nil)
    }

    @Test func aProfileWithNoPlistInItLeavesTheDeviceToTheDeclaration() {
        // Nil rather than empty, and the distinction is the whole safety of
        // the profile read: an empty dictionary would read as "grants
        // nothing" and withhold Private Cloud Compute from an entitled app
        // that declared it.
        #expect(AskProcessEntitlements.reading(AskProcessEntitlements.privateCloudCompute, inProfile: nil)
                == .unreadable)
        #expect(AskProcessEntitlements.entitlements(inProvisioningProfile: Data()) == nil)
        #expect(AskProcessEntitlements.entitlements(
            inProvisioningProfile: Data([0x30, 0x82, 0x0A, 0xBC])
        ) == nil)
        // Truncated: the opening tag is there and the closing one is not.
        #expect(AskProcessEntitlements.entitlements(
            inProvisioningProfile: Data("<?xml version=\"1.0\"?><plist><dict>".utf8)
        ) == nil)
    }

    @Test func aProfileWithNoEntitlementsDictionaryIsNotAGrantOfNothing() {
        let data = Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict>
            <key>Name</key><string>Some profile</string>
            </dict></plist>
            """.utf8)
        #expect(AskProcessEntitlements.entitlements(inProvisioningProfile: data) == nil)
    }

    @Test func theKeyIsApplesOwnSpelling() {
        // A typo here disables the guard silently, and the string is the only
        // thing tying this to the capability.
        #expect(AskProcessEntitlements.privateCloudCompute == "com.apple.developer.private-cloud-compute")
    }

    @Test func theCachedReadingAgreesWithAFreshRead() {
        // `privateCloudComputeReading` is a `static let` over `reading`.
        // Entitlements do not change while a process runs, so these must not
        // disagree.
        #expect(AskProcessEntitlements.privateCloudComputeReading
                == AskProcessEntitlements.reading(AskProcessEntitlements.privateCloudCompute))
    }

    // MARK: - Development signing, which the park reads

    /// A profile whose `get-task-allow` is spelled out, the way both kinds
    /// carry it: `<true/>` in a development profile, `<false/>` in an ad hoc or
    /// App Store one.
    private func profile(getTaskAllow: Bool) -> Data {
        let value = getTaskAllow ? "<true/>" : "<false/>"
        return Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict>
            <key>Entitlements</key><dict><key>get-task-allow</key>\(value)</dict>
            </dict></plist>
            """.utf8)
    }

    @Test func aDevelopmentProfileIsDevelopmentSigned() {
        // A Profile run and a hand-installed Release build carry the
        // development profile, whose `get-task-allow` lets the debugger attach.
        let granted = AskProcessEntitlements.entitlements(inProvisioningProfile: profile(getTaskAllow: true))
        #expect(AskProcessEntitlements.isDevelopment(profileEntitlements: granted))
    }

    @Test func aDistributionProfileIsNotEvenThoughItNamesTheKey() {
        // **The value, not the presence.** `reading(_:inProfile:)` reads a
        // profile's keys as grants, which is right for a capability; an ad hoc
        // profile lists `get-task-allow` as false, and read by its presence it
        // would be parked.
        let granted = AskProcessEntitlements.entitlements(inProvisioningProfile: profile(getTaskAllow: false))
        #expect(!AskProcessEntitlements.isDevelopment(profileEntitlements: granted))
    }

    @Test func noProfileAtAllIsTheShippedBuild() {
        // App Store and TestFlight distribution strip `embedded.mobileprovision`.
        #expect(!AskProcessEntitlements.isDevelopment(profileEntitlements: nil))
    }
}
