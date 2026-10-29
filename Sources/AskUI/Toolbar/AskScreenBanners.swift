#if os(iOS) || os(macOS) || os(visionOS)

public import SwiftUI

/// The banners over the conversation, the quota's and the unreadable chat's,
/// and the first screen or the thread under them (`AskScreen.conversation`).
///
/// **At the accessibility sizes the banners take at most half the height, and
/// scroll in it.** Outside every scroll view, a banner takes the height it
/// needs out of the thread's, and at those sizes that can be all of it: the
/// quota's sentence with "Show options" under it runs to several hundred
/// points on a phone, more than the thread has between the bars on its side,
/// and the unreadable chat's sentence, which can be squeezed, is cut off
/// instead. A stack offers the less flexible of its two children half its
/// height first, and the content under the banners takes any height, so
/// banners that fit in that half are drawn as they are, and banners that
/// don't scroll in it. Half is what the stack gives, chosen rather than
/// measured on a device; `AskScreenBannersTests` holds the layout to it.
///
/// **A scroll view only while they don't fit** (`ViewThatFits`), so at every
/// other size, and at these whenever the banners fit, the screen is as it was.
/// Whether the navigation bar follows that second scroll view for its edge
/// effect or its minimizing, while it is there, hasn't been looked at.
///
/// **Not in the content's scroll view.** The quota is a fact about the next
/// question, which is asked at the foot of the thread, and at the top of a
/// long thread's content the banner would scroll away out of sight.
struct AskScreenBanners<Banners: View, Content: View>: View {
    private let banners: Banners
    private let content: Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(@ViewBuilder banners: () -> Banners, @ViewBuilder content: () -> Content) {
        self.banners = banners()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            if dynamicTypeSize.isAccessibilitySize {
                // Each candidate one view, since `ViewThatFits` takes each of
                // its children as a candidate, and the banners are two.
                ViewThatFits(in: .vertical) {
                    VStack(spacing: 0) { banners }
                    ScrollView {
                        VStack(spacing: 0) { banners }
                    }
                }
            } else {
                banners
            }
            content
        }
    }
}

#endif
