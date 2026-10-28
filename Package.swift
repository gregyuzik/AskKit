// swift-tools-version: 6.4
import PackageDescription

// The posture every target here builds under except `AskCrossPostureTests`:
// main-actor default isolation, the two upcoming features Approachable
// Concurrency adds to Swift 6 (`NonisolatedNonsendingByDefault` and
// `InferIsolatedConformances`), `MemberImportVisibility` and `ExistentialAny`.
// Consumers need not share the posture: AskCore's public API states its
// isolation explicitly (actors, `nonisolated`, `@Sendable` closures, `Sendable`
// values), so a package that leaves `NonisolatedNonsendingByDefault` off still
// compiles against it. A "call to main actor-isolated … in a synchronous
// nonisolated context" in a consumer is an AskCore API bug, not a consumer bug.
let approachable: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("ExistentialAny")
]

// All five platforms, even though only iOS, macOS and visionOS ever show Ask:
// a host's shared package that builds for tvOS or watchOS still depends on
// AskCore. Every FoundationModels file is
// `#if canImport(FoundationModels) && !os(tvOS)`, with `&& !os(watchOS)` around
// `SystemLanguageModel` (the watch has the framework, not the model) and
// `LanguageModelSession.ToolCallError` (unavailable there); every AskUI view
// file is `#if os(iOS) || os(macOS) || os(visionOS)`.
let package = Package(
    name: "AskKit",
    defaultLocalization: "en",
    platforms: [.iOS("27.2"), .macOS("27.2"), .visionOS("27.2"), .tvOS("27.2"), .watchOS("27.2")],
    products: [
        .library(name: "AskCore", targets: ["AskCore"]),
        .library(name: "AskUI", targets: ["AskUI"])
    ],
    targets: [
        .target(
            name: "AskCore",
            path: "Sources/AskCore",
            resources: [.process("Resources")],
            swiftSettings: approachable
        ),
        .target(
            name: "AskUI",
            dependencies: ["AskCore"],
            path: "Sources/AskUI",
            resources: [.process("Resources")],
            swiftSettings: approachable
        ),
        .testTarget(
            name: "AskCoreTests",
            dependencies: ["AskCore"],
            path: "Tests/AskCoreTests",
            swiftSettings: approachable
        ),
        .testTarget(
            name: "AskUITests",
            dependencies: ["AskUI"],
            path: "Tests/AskUITests",
            swiftSettings: approachable
        ),
        // **No `swiftSettings`, deliberately.** Nonisolated default isolation,
        // none of the upcoming features — the posture a consumer that does not
        // share ours compiles under.
        //
        // Everything above carries the identical approachable posture, so this
        // is the only target that fails to compile when public API it calls
        // loses its explicit isolation. Without it an AskCore change could pass
        // here and fail only in a consumer's build. Giving this target settings
        // stops it testing anything.
        .testTarget(
            name: "AskCrossPostureTests",
            dependencies: ["AskCore", "AskUI"],
            path: "Tests/AskCrossPostureTests"
        )
    ]
)
