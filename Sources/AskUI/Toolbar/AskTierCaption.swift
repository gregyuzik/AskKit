#if os(iOS) || os(macOS) || os(visionOS)

import AskCore
import SwiftUI

/// Which tier is answering: the navigation subtitle, or a caption leading the
/// bar where the title has no room to show it.
///
/// **Under a tab bar at the top, the caption leads the bar instead.** On an
/// iPad at regular width a `TabView` puts its tab bar in the navigation bar's
/// row, in the middle, where the title and its subtitle would stand, and
/// neither is drawn. A host usually puts Ask in a tab, so without this a
/// regular-width window would never say which tier was answering. There the
/// caption takes the bar's leading edge, as it does on visionOS. The switch is
/// keyed on `tabBarPlacement`, not on the idiom or the width. A window
/// narrowed to compact width moves the tab bar to the bottom, and the caption
/// goes back under the title. Both modifiers stay applied either way, so
/// moving the caption never rebuilds the screen.
///
/// **The line is always applied, even when there is nothing to say.** A
/// subtitle that appears when the tier resolves changes the navigation bar's
/// height mid-turn, and the whole thread jumps. `Text(verbatim: "")` reserves
/// the line.
///
/// **The tier's name alone, not a sentence about it.** On an iPhone 17 Pro,
/// "Answering with Private Cloud Compute" takes 213 pt of a 361 pt bar, which
/// leaves room for one narrow toolbar item before the title stops centering:
/// New Chat, and not Done as well. The name alone takes 128 pt, and a
/// subtitle already reads as a caption on the title above it, so under the
/// title, "Private Cloud Compute" says what the sentence would. The words the
/// caption leaves out are what pay for Done.
public struct AskTierCaption: ViewModifier {
    private let tier: AskTier?

    #if os(iOS)
    @Environment(\.tabBarPlacement) private var tabBarPlacement
    #endif

    /// Creates the caption.
    ///
    /// - Parameter tier: The tier to name, such as the store's `captionTier`.
    ///   Nil names nothing, and where the caption is the subtitle its line
    ///   stays, so the bar keeps its height.
    public init(tier: AskTier?) {
        self.tier = tier
    }

    public func body(content: Content) -> some View {
        #if os(visionOS)
        // A visionOS ornament has no subtitle, so the caption is a toolbar
        // label instead.
        content.toolbar {
            ToolbarItem(placement: .topBarLeading) { label }
        }
        #elseif os(iOS)
        content
            // Emptied rather than removed while the caption leads the bar,
            // since the line is always applied (the note above says why).
            .navigationSubtitle(leadsTheBar ? Text(verbatim: "") : subtitle)
            .toolbar {
                if leadsTheBar {
                    ToolbarItem(placement: .topBarLeading) {
                        // The bar offers an item less than the caption's
                        // width, and without this "On device" breaks over two
                        // lines.
                        label.fixedSize()
                    }
                    // A caption, not a control, so no glass behind it.
                    .sharedBackgroundVisibility(.hidden)
                }
            }
        #else
        content.navigationSubtitle(subtitle)
        #endif
    }

    #if os(iOS)
    /// The tab bar has the title's place, so the caption can't go under it.
    private var leadsTheBar: Bool {
        tabBarPlacement == .topBar
    }
    #endif

    #if os(iOS) || os(visionOS)
    /// The caption as a bar item.
    @ViewBuilder
    private var label: some View {
        if let name = Self.name(tier) {
            // Verbatim for the same reason the subtitle is.
            // On the bar's own ground, with no glass behind it
            // (`sharedBackgroundVisibility`), so the gray that clears the
            // contrast bar there rather than `.secondary` (`askDeemphasizedText`).
            Text(verbatim: name)
                .font(.caption)
                .askDeemphasizedText()
        }
    }
    #endif

    private var subtitle: Text {
        guard let name = Self.name(tier) else { return Text(verbatim: "") }
        // `Text(verbatim:)` because `name` is already localized: both tier
        // names come from AskUI's catalog, and one of them is Apple's product
        // name, which is never translated.
        return Text(verbatim: name)
    }

    /// The reader-facing name of a tier, localized from AskUI's catalog.
    /// "Private Cloud Compute" is Apple's own and is never translated.
    ///
    /// - Parameter tier: The tier to name.
    /// - Returns: The tier's name, or nil when `tier` is nil.
    public static func name(_ tier: AskTier?) -> String? {
        switch tier {
        case .privateCloud:
            return String(localized: "Private Cloud Compute", bundle: #bundle, comment: "Apple's product name. Not translated.")
        case .onDevice:
            return String(localized: "On device", bundle: #bundle, comment: "Names the tier answering an Ask question: the model running on this device rather than in Private Cloud Compute.")
        case nil:
            return nil
        }
    }
}

extension View {
    /// Names the tier answering in the navigation bar, without letting the bar
    /// change height when it resolves (`AskTierCaption`).
    ///
    /// - Parameter tier: The tier to name, such as the store's `captionTier`.
    ///   Nil names nothing, and where the caption is the subtitle its line
    ///   stays, so the bar keeps its height.
    public func askTierCaption(_ tier: AskTier?) -> some View {
        modifier(AskTierCaption(tier: tier))
    }
}

#endif
