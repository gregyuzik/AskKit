#if os(iOS) || os(macOS) || os(visionOS)

public import SwiftUI

// Why AskUI wraps SwiftUI's glass API rather than calling it: AskGlass.swift.

/// One glass group, so the shapes inside it blend and morph as a set rather
/// than as separate pieces.
///
/// **One per bank of chips, and one around each glass surface that comes and
/// goes on its own**, a banner or the pill, holding that surface alone so its
/// glass can materialize (`askGlassTransition(reduceMotion:)`). Nowhere else:
/// a container that wraps the whole screen makes every glass surface on it a
/// candidate for blending with every other, which is how a composer ends up
/// bleeding into a toolbar. On visionOS it adds nothing, since glass there
/// doesn't blend.
struct AskGlassGroup<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    init(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        #if os(visionOS)
        content
        #else
        GlassEffectContainer(spacing: spacing) { content }
        #endif
    }
}

extension View {
    /// Ties a glass shape to an identity in `namespace`, so it morphs into the
    /// next shape with the same id rather than fading out and in. Nothing on
    /// visionOS.
    @ViewBuilder
    func askGlassID(_ id: some Hashable & Sendable, in namespace: Namespace.ID) -> some View {
        #if os(visionOS)
        self
        #else
        glassEffectID(id, in: namespace)
        #endif
    }

    /// How a glass shape enters and leaves: it materializes. Nothing on
    /// visionOS, where glass appears as an object rather than as a surface
    /// effect.
    @ViewBuilder
    func askGlassMaterialize() -> some View {
        #if os(visionOS)
        self
        #else
        glassEffectTransition(.materialize)
        #endif
    }

    /// How a glass surface that comes and goes on its own enters and leaves,
    /// a banner or the pill: its glass materializes, inside an `AskGlassGroup`
    /// of its own that outlives it, since a glass transition is the
    /// container's to run.
    ///
    /// **Materialized, not faded or blurred as a view**, so the glass comes
    /// and goes as the system's own does rather than as a picture of it. Apple
    /// gives `.materialize` for glass with no neighbor to morph from
    /// ("Applying Liquid Glass to custom views"): it comes up in place, with
    /// no geometry carried from anywhere, so nothing travels, and Reduce
    /// Motion takes it as it is (house rule 8).
    ///
    /// On visionOS, which has none of it, an opacity and blur transition, and
    /// opacity alone under Reduce Motion.
    /// Neither platform's look has been watched on a simulator.
    @ViewBuilder
    func askGlassTransition(reduceMotion: Bool) -> some View {
        #if os(visionOS)
        transition(reduceMotion ? AnyTransition(.opacity) : AnyTransition(.blurReplace))
        #else
        askGlassMaterialize()
        #endif
    }
}

#endif
