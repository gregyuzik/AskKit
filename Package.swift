// swift-tools-version: 6.4
import PackageDescription

// The posture every target here builds under except `AskCrossPostureTests`:
// the Swift 6 language mode with main-actor default isolation, plus all six
// upcoming features this compiler has from Swift 7. Two are what Approachable
// Concurrency adds to Swift 6 (`NonisolatedNonsendingByDefault` and
// `InferIsolatedConformances`); the other four are `MemberImportVisibility`,
// `ExistentialAny`, `InternalImportsByDefault` (an `import` is internal, so a
// file writes `public import` only for a module a public or `@inlinable`
// signature names, and `package import` for one only a `package` signature
// does) and `ImmutableWeakCaptures` (a `weak` capture is a `let`).
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
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("ImmutableWeakCaptures")
]

// AskKit's own code, the libraries and their tests, also builds with strict
// memory safety: each unsafe use is marked `unsafe`, with why it is sound, and
// an unmarked one is a warning the push gate fails on. Not the README's
// samples in `AskReadmeApproachableTests`: they are a host's code, Xcode's app
// template doesn't turn it on, and their `String(format:)` would take an
// `unsafe` no adopter needs.
let memorySafe: [SwiftSetting] = approachable + [.strictMemorySafety()]

// All five platforms, even though only iOS, macOS and visionOS ever show Ask:
// a host's shared package that builds for tvOS or watchOS still depends on
// AskCore. Every FoundationModels file is
// `#if canImport(FoundationModels) && !os(tvOS)`, with `&& !os(watchOS)` around
// `SystemLanguageModel` (the watch has the framework, not the model),
// `LanguageModelSession.ToolCallError` and `GenerationError` (unavailable
// there); every AskUI view file is `#if os(iOS) || os(macOS) || os(visionOS)`.
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
            swiftSettings: memorySafe
        ),
        .target(
            name: "AskUI",
            dependencies: ["AskCore"],
            path: "Sources/AskUI",
            resources: [.process("Resources")],
            swiftSettings: memorySafe
        ),
        .testTarget(
            name: "AskCoreTests",
            dependencies: ["AskCore"],
            path: "Tests/AskCoreTests",
            swiftSettings: memorySafe
        ),
        .testTarget(
            name: "AskUITests",
            dependencies: ["AskUI"],
            path: "Tests/AskUITests",
            swiftSettings: memorySafe
        ),
        // **No `swiftSettings`, deliberately.** Nonisolated default isolation,
        // none of the upcoming features — the posture a consumer that does not
        // share ours compiles under.
        //
        // Every other target carries the identical approachable posture, so
        // this is the only one that fails to compile when public API it calls
        // loses its explicit isolation. Without it an AskCore change could pass
        // here and fail only in a consumer's build. Giving this target settings
        // stops it testing anything.
        .testTarget(
            name: "AskCrossPostureTests",
            dependencies: ["AskCore", "AskUI"],
            path: "Tests/AskCrossPostureTests"
        ),
        // README.md's two samples, built and run again under the approachable
        // posture, which a host on Xcode's app template has too (main-actor
        // default isolation, `NonisolatedNonsendingByDefault`), so the code an
        // adopter copies is proven in that posture as well as in none.
        //
        // The folder holds two symlinks to `AskCrossPostureTests`'
        // `ReadmeDomain.swift` and `ReadmeAssistantDomain.swift`, so the
        // README's word-for-word check still compares one file each. SwiftPM
        // reads `sources:` only inside a target's own path, and a target at
        // `Tests/` overlaps every other. A link that stops reaching its file
        // is a warning that names the package, which the push gate fails on.
        //
        // It doesn't prove that the samples need their `nonisolated` or
        // `@concurrent`: with either taken off any one type or `call`, this
        // target and `AskCrossPostureTests` still build and pass. Under Swift
        // 6.4 a type conforming to a `nonisolated` protocol such as `AskRow` is
        // `nonisolated` without the keyword, and a `call` that isn't
        // `@concurrent` still satisfies `Tool`.
        .testTarget(
            name: "AskReadmeApproachableTests",
            dependencies: ["AskCore", "AskUI"],
            path: "Tests/AskReadmeApproachableTests",
            swiftSettings: approachable
        )
    ]
)
