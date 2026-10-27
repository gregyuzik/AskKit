import Foundation

/// Whether this build may show developer rows.
///
/// **In AskCore, and behind no platform gate.** It is a fact about the
/// process, the same kind of thing `AskProcessEntitlements` is, not a view.
/// So a host's shared code can ask on every platform, and a host that runs
/// `AskEval` without the settings card can ask without importing AskUI.
///
/// **A runtime read, never `#if DEBUG` around the code it turns on.** A
/// TestFlight build is a Release build, and a signed build on a device is the
/// only place Private Cloud Compute can actually be measured, so the eval has
/// to be reachable there. `#if DEBUG` decides only `isDebugBuild`.
nonisolated public enum AskDiagnostics {
    /// A Debug build, or a TestFlight one, or a host that has turned the rows
    /// on for itself. It turns on the settings card's diagnostics rows (the
    /// default for `AskPrivateCloudCard`'s `showsDiagnostics`) and the thumbs
    /// under answers (`AskConversationStore.offersFeedback`).
    ///
    /// Main-actor because `enabledByApp` is: a host flips it at launch and the
    /// card reads it while drawing, which is the same actor either way.
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

    /// Whether the bundle carries the sandbox receipt TestFlight leaves in it.
    ///
    /// Read as a file rather than through `Bundle.appStoreReceiptURL`, which is
    /// deprecated **for Swift only** (`NSBundle.h` splits on `__swift__`), so
    /// reading it would warn, and AskKit builds with zero warnings. The path is
    /// the one that property returns. On macOS a TestFlight build carries its
    /// receipt at `_MASReceipt/receipt` instead, so this check is false there:
    /// Mac diagnostics go through `enabledByApp`.
    public static let isTestFlight: Bool = {
        let receipt = Bundle.main.bundleURL.appending(path: "StoreKit/sandboxReceipt")
        return FileManager.default.fileExists(atPath: receipt.path(percentEncoded: false))
    }()
}
