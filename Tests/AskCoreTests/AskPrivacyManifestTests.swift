import Foundation
import Testing

@testable import AskCore

/// AskCore's privacy manifest, read from the package's resources as a host app
/// gets them. An app's privacy report is built from the manifests in its
/// bundle, and Apple requires an SDK to declare its own required-reason API in
/// its own manifest, so this is AskKit's part of every host's report.
///
/// The declarations are AskCore's two required-reason calls, and nothing else:
/// - `UserDefaults`, for CA92.1: `AskDevelopmentPark` reads the argument
///   domain, this launch's own arguments, for `ASK_LIVE_PCC`.
/// - the file timestamp, for C617.1: `AskThreadArchive` reads the
///   `contentModificationDateKey` of a chat file in the app's own Application
///   Support folder, the date of an earlier chat its index doesn't list.
///
/// AskUI calls none, and carries no manifest. A new required-reason call
/// changes this table and the manifest together.
@Suite(.timeLimit(.minutes(1))) struct AskPrivacyManifestTests {
    private static var manifest: [String: Any] {
        guard let url = Bundle.module.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
              let data = try? Data(contentsOf: url),
              // `unsafe`: `format:` is a pointer to write the format through; nil writes nothing.
              let plist = (try? unsafe PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
        else { preconditionFailure("the package ships PrivacyInfo.xcprivacy as a property list") }
        return plist
    }

    @Test func declaresEachRequiredReasonCallWithItsReason() throws {
        let entries = try #require(Self.manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        var declared: [String: [String]] = [:]
        for entry in entries {
            let category = try #require(entry["NSPrivacyAccessedAPIType"] as? String)
            let reasons = try #require(entry["NSPrivacyAccessedAPITypeReasons"] as? [String])
            #expect(declared[category] == nil, "\(category) is declared twice")
            declared[category] = reasons
        }
        #expect(declared == [
            "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
            "NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"]
        ])
    }

    @Test func tracksNothingAndCollectsNothing() throws {
        // AskKit sends nothing to its developer or any third party: answers
        // come from Apple's Foundation Models, and the host owns its data.
        #expect(Self.manifest["NSPrivacyTracking"] as? Bool == false)
        let domains = try #require(Self.manifest["NSPrivacyTrackingDomains"] as? [Any])
        #expect(domains.isEmpty)
        let collected = try #require(Self.manifest["NSPrivacyCollectedDataTypes"] as? [Any])
        #expect(collected.isEmpty)
    }
}
