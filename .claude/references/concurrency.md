# Concurrency posture

- **AskKit's posture, and a host's.** AskKit builds with `.defaultIsolation(MainActor.self)`,
  `NonisolatedNonsendingByDefault`, `InferIsolatedConformances`, `MemberImportVisibility` and
  `ExistentialAny`. A host needn't: its package may keep nonisolated default isolation, or leave
  `NonisolatedNonsendingByDefault` off. A host compiles against AskCore only while AskCore's public API
  states its isolation explicitly: actors, `nonisolated`, `@Sendable` closures and `Sendable` values.
- **`nonisolated` everywhere public.** Every public enum, struct, protocol and extension in AskCore is
  `nonisolated`, and so is anything internal that runs off the main actor. That includes:
  - the `AskDomain` defaults extension;
  - statics read off the main actor. A struct's or a class's static is main-actor isolated without it.
    An actor's statics take no default isolation, so `AskGenerationGate.shared` spells `nonisolated`
    only to say what is already true (measured on Swift 6.4);
  - internal types used off the main actor, such as `NetworkReachability` in `AppleModelSeam.swift`.

  Without it, `InferIsolatedConformances` gives a public struct, or an enum with associated values, a
  main-actor-isolated synthesized `Codable` and `Equatable`. An off-main decode refuses that, whether
  `AskThreadStore`'s or a host's. A `String` raw-value enum, measured, keeps `Codable`, `Equatable`,
  `Hashable` and `allCases` usable anywhere; only its own members turn main-actor isolated. The exceptions
  are the actors, and `AskModelStatus`, which is `@MainActor @Observable` on purpose.
- **Only one target can catch it.** The other test targets share the posture, so they can't catch a
  missing `nonisolated`. `AskCrossPostureTests` has no `swiftSettings`, on purpose: it fails to compile
  when API it calls has lost its `nonisolated`. Add each new public type or conformance there, and never
  give that target settings. SPI (`@_spi(AskKitInternal)`) keeps its `nonisolated` spelling too, and
  `CrossPostureSPITests.swift` calls it: SPI is seen per file, so it has a file of its own.
- **A protocol requirement spells its closure's isolation.** `AskModelSeam.withGeneration` takes a
  `nonisolated(nonsending) @Sendable` body, not a plain `@Sendable` one. Under
  `NonisolatedNonsendingByDefault` the two are the same type, but a host without the feature sees two
  types. A conformance that copies the requirement conforms under either posture, where one spelled
  plain `@Sendable` would match only under the feature.
- **`@concurrent`.** Code written assuming a `nonisolated async` function runs on the global executor
  compiles here, then runs on the main actor. Tool bodies and file I/O are the usual cases, and each
  needs `@concurrent`.
