import Foundation
#if os(macOS)
import Security
#endif
#if targetEnvironment(simulator)
import MachO
#endif

/// Whether the host's app holds the Private Cloud Compute entitlement, as the
/// host declares it to `AppleModelSeam`.
///
/// **Declared, because a shipped build can't read its own.** A request from a
/// process without `com.apple.developer.private-cloud-compute` is not an error
/// but a fatal trap ("Missing entitlement"). On an iPhone, an iPad or an Apple
/// Vision Pro the only thing a build can read about its entitlements is the
/// provisioning profile beside it, and TestFlight and App Store distribution
/// strip that profile. So the host says, and the seam believes it wherever
/// nothing the build can read says otherwise (`AskProcessEntitlements`).
nonisolated public enum AskPrivateCloudCompute: Sendable, Equatable {
    /// The app's entitlements file claims
    /// `com.apple.developer.private-cloud-compute`, and its provisioning
    /// profile grants it. The seam may send Private Cloud Compute requests,
    /// unless the build proves the entitlement absent.
    case declared
    /// The app doesn't hold the entitlement. The seam sends Private Cloud
    /// Compute nothing, the tier reads `.notEntitled`, and every question goes
    /// to the on-device model.
    case undeclared
}

/// What this process is entitled to, read from the running build and never
/// from the project's entitlements file, because the two can differ: macOS
/// signing drops an entitlement the provisioning profile doesn't grant and
/// still reports a green build, and an unsigned simulator build carries none
/// at all.
///
/// A Private Cloud Compute request from a process without the entitlement is
/// a **fatal** trap at request time ("Missing entitlement"), in a simulator
/// app and, on macOS 27, in a command-line tool too. So the seam asks this
/// before it sends one. Constructing the model and reading its availability
/// are safe either way: measured on macOS 27, an unentitled process reads
/// `.available`, which is why availability proves nothing about the
/// entitlement.
///
/// Three reads, one per way a build carries its entitlements:
/// - macOS reads its own `SecTask`, the public API for this;
/// - a simulator build carries them as the `__TEXT,__entitlements` section
///   Xcode embeds;
/// - a device has no supported way to read its own entitlements, so it reads
///   the provisioning profile beside the app, the upper bound of what the
///   binary can hold. A build with no profile reads nothing, and the host's
///   declaration decides (`AskPrivateCloudCompute`).
///
/// Behind no platform gate: the answer is a fact about the build, not about
/// Foundation Models, and a tvOS or watchOS host asking it needs no
/// framework.
nonisolated public enum AskProcessEntitlements {
    /// The Private Cloud Compute entitlement's key,
    /// `com.apple.developer.private-cloud-compute`.
    public static let privateCloudCompute = "com.apple.developer.private-cloud-compute"

    /// What the running build says about one entitlement key.
    nonisolated enum Reading: Equatable, Sendable {
        /// The build carries the key. On macOS and in a simulator that is the
        /// binary's own signature; on a device, the provisioning profile grants
        /// it, which is an upper bound rather than proof.
        case present
        /// The build proves it doesn't carry the key: its signature lacks it,
        /// or its provisioning profile doesn't grant it, and a binary can't be
        /// signed with an entitlement its profile doesn't grant.
        case absent
        /// Nothing says: a device build with no provisioning profile beside
        /// it, which is every TestFlight and App Store build.
        case unreadable
    }

    /// What this build says about Private Cloud Compute. Read once:
    /// entitlements don't change while a process runs.
    static let privateCloudComputeReading: Reading = reading(privateCloudCompute)

    /// Why this process must not send Private Cloud Compute a request, or nil
    /// when it may: only when the host declared the entitlement and the build
    /// doesn't prove it absent.
    ///
    /// **An exact reading outranks the declaration, and the declaration
    /// decides where nothing can be read.** A build whose signature or profile
    /// lacks the key would trap on the request, whatever the host says. A
    /// build with no profile has only the declaration to go on: one that
    /// declares an entitlement it doesn't hold traps on its first Private
    /// Cloud Compute request, and that is the host's to fix. An undeclared
    /// entitlement is never used, whatever the build carries.
    static func privateCloudComputeRefusal(_ declaration: AskPrivateCloudCompute, reading: Reading) -> String? {
        switch (declaration, reading) {
        case (.undeclared, _): "undeclared by the host"
        case (.declared, .absent): "declared by the host, and this build doesn't carry \(privateCloudCompute)"
        case (.declared, .present), (.declared, .unreadable): nil
        }
    }

    /// Whether this binary is signed for development: it carries
    /// `get-task-allow`, the entitlement that lets a debugger attach, which no
    /// TestFlight or App Store build does. `AskDevelopmentPark` reads it to
    /// park a Profile run, or a Release build installed by hand, that neither
    /// the configuration nor the simulator check catches.
    ///
    /// **The value, not the key's presence,** even on a device, where
    /// `reading(_:)` goes by presence (`reading(_:inProfile:)`). An ad hoc
    /// profile lists `get-task-allow` as false.
    public static let isDevelopmentSigned: Bool = readsDevelopmentSigned()

    /// The read behind `isDevelopmentSigned`, by the same three reads as
    /// `reading(_:)`.
    static func readsDevelopmentSigned() -> Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let key = "com.apple.security.get-task-allow" as CFString
        return (SecTaskCopyValueForEntitlement(task, key, nil) as? Bool) == true
        #elseif targetEnvironment(simulator)
        return (embeddedEntitlements()?["get-task-allow"] as? Bool) == true
        #else
        return isDevelopment(profileEntitlements: provisionedEntitlements())
        #endif
    }

    /// Whether a provisioning profile's entitlements are a development
    /// profile's. No profile at all is the shipped build: App Store and
    /// TestFlight distribution strip `embedded.mobileprovision`.
    static func isDevelopment(profileEntitlements: [String: Any]?) -> Bool {
        (profileEntitlements?["get-task-allow"] as? Bool) == true
    }

    /// What the running build says about `key`.
    ///
    /// Not `public`: on a device it answers from the provisioning profile,
    /// which is an upper bound for **any** key rather than a reading of one,
    /// and that is a good answer about one known capability and a bad
    /// general-purpose API. The seam weighs it against the host's declaration
    /// (`privateCloudComputeRefusal(_:reading:)`).
    static func reading(_ key: String) -> Reading {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return .absent }
        return (SecTaskCopyValueForEntitlement(task, key as CFString, nil) as? Bool) == true ? .present : .absent
        #elseif targetEnvironment(simulator)
        return (embeddedEntitlements()?[key] as? Bool) == true ? .present : .absent
        #else
        return reading(key, inProfile: provisionedEntitlements())
        #endif
    }

    /// A device's reading of `key`, from what its provisioning profile grants,
    /// or `.unreadable` for a build with no profile.
    ///
    /// **Presence, not `== true`:** the profile grants a capability, and a
    /// grant is the key being listed. Behind no platform gate, and separate
    /// from `reading(_:)`, so the device's answer is testable on entitlements
    /// a test supplies.
    static func reading(_ key: String, inProfile profileEntitlements: [String: Any]?) -> Reading {
        guard let profileEntitlements else { return .unreadable }
        return profileEntitlements[key] != nil ? .present : .absent
    }

    #if targetEnvironment(simulator)
    /// The entitlements plist Xcode embeds in the main executable of a signed
    /// simulator build, or nil for an unsigned build, which embeds nothing.
    ///
    /// It reads the first image of type `MH_EXECUTE`, the main executable,
    /// and never a dylib. When Xcode builds a Debug app as a stub executable
    /// that loads the app's code from a `.debug.dylib`, the stub is the image
    /// that carries the signature.
    static func embeddedEntitlements() -> [String: Any]? {
        // `unsafe` throughout: dyld answers in raw pointers into the loaded
        // images, and the one read here is the main executable's, loaded for
        // the life of the process.
        for index in 0..<_dyld_image_count() {
            guard let header = unsafe _dyld_get_image_header(index),
                  unsafe header.pointee.filetype == UInt32(MH_EXECUTE) else { continue }
            var size: UInt = 0
            let bytes = unsafe UnsafeRawPointer(header).withMemoryRebound(to: mach_header_64.self, capacity: 1) { header64 in
                unsafe getsectiondata(header64, "__TEXT", "__entitlements", &size)
            }
            guard let bytes = unsafe bytes, size > 0 else { return nil }
            // Copies the section's `size` bytes out, so nothing outlives the read.
            let data = unsafe Data(bytes: bytes, count: Int(size))
            // `unsafe`: `format:` is a pointer to write the format through; nil writes nothing.
            return (try? unsafe PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
        }
        return nil
    }
    #endif

    /// What the provisioning profile beside the binary grants.
    ///
    /// Behind no platform gate, unlike the two reads above, because it needs
    /// no import and nothing about it is platform-specific: a bundle either
    /// has an `embedded.mobileprovision` or it doesn't. Only the device
    /// branches of `reading(_:)` and `readsDevelopmentSigned()` ask.
    static func provisionedEntitlements() -> [String: Any]? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe)
        else { return nil }
        return entitlements(inProvisioningProfile: data)
    }

    /// The `Entitlements` dictionary inside a provisioning profile.
    ///
    /// **The plist sits inside a CMS signature, and is found rather than
    /// verified.** Decoding the container properly needs `Security`, which
    /// this file imports on macOS alone, for `SecTask`, and would buy nothing:
    /// the profile is a file in the app's own bundle, so there is no attacker
    /// to authenticate it against, and everything read from it is used to
    /// withhold a request, never to grant one. The worst a malformed profile
    /// can do is read as no profile, which leaves the host's declaration to
    /// decide.
    ///
    /// Separate from `provisionedEntitlements()` so the parsing is testable on
    /// profile data a test supplies.
    static func entitlements(inProvisioningProfile data: Data) -> [String: Any]? {
        guard let start = data.range(of: Data("<?xml".utf8))?.lowerBound,
              let end = data.range(of: Data("</plist>".utf8), options: .backwards)?.upperBound,
              start < end
        else { return nil }
        // `unsafe`: `format:` is a pointer to write the format through; nil writes nothing.
        let plist = try? unsafe PropertyListSerialization.propertyList(
            from: Data(data[start..<end]), format: nil
        )
        return (plist as? [String: Any])?["Entitlements"] as? [String: Any]
    }
}
