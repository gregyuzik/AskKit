#if os(iOS) || os(macOS) || os(visionOS)

import SwiftUI
import Testing

@testable import AskUI

/// The banners over the conversation leave the conversation room at the
/// accessibility sizes: what is left for the content under them, read off a
/// render.
///
/// A conversation 600 pt tall, as an iPhone 18 Pro's is upright between its
/// bars, with a banner of a given height standing in for the quota's or the
/// unreadable chat's: 500 pt is about what the quota's stacked to at the
/// largest size.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct AskScreenBannersTests {

    private static let conversation: CGFloat = 600

    /// The height the content under the banners was laid out at.
    private final class Measured {
        var contentHeight: CGFloat?
    }

    private func contentHeight(banner: CGFloat?, at size: DynamicTypeSize) throws -> CGFloat {
        let measured = Measured()
        let screen = AskScreenBanners {
            if let banner {
                Color.black.frame(height: banner)
            }
        } content: {
            GeometryReader { proxy in
                measured.contentHeight = proxy.size.height
                return Color.red
            }
        }
        .environment(\.dynamicTypeSize, size)
        let renderer = ImageRenderer(content: screen)
        renderer.proposedSize = ProposedViewSize(width: 300, height: Self.conversation)
        _ = try #require(renderer.cgImage)
        return try #require(measured.contentHeight, "the content was laid out")
    }

    @Test func atTheLargestSizeABannerTallerThanHalfLeavesTheContentHalf() throws {
        // Where the banner sat outside any scroll view at its whole height, the
        // thread had 100 pt here, and on a phone on its side none at all.
        #expect(try contentHeight(banner: 500, at: .accessibility5) == Self.conversation / 2)
    }

    @Test func atAnAccessibilitySizeABannerThatFitsIsDrawnWhole() throws {
        #expect(try contentHeight(banner: 120, at: .accessibility1) == Self.conversation - 120)
    }

    @Test func belowTheAccessibilitySizesABannerTakesWhatItNeeds() throws {
        // Unchanged from before: a banner at these sizes is a few lines, and
        // the cap is for the sizes where it isn't.
        #expect(try contentHeight(banner: 500, at: .xxxLarge) == Self.conversation - 500)
    }

    @Test func withNoBannerTheContentHasTheWholeHeight() throws {
        #expect(try contentHeight(banner: nil, at: .accessibility5) == Self.conversation)
        #expect(try contentHeight(banner: nil, at: .large) == Self.conversation)
    }

    @Test func aGlassGroupHoldingNothingTakesNoHeight() throws {
        // A banner away, and the photo chip over the composer, leave their
        // glass groups behind with nothing in them, so that their glass can
        // materialize when they come back (`askGlassTransition`). The screen
        // is laid out as if the groups weren't there.
        for size in [DynamicTypeSize.large, .accessibility5] {
            let measured = Measured()
            let screen = AskScreenBanners {
                AskGlassGroup { EmptyView() }
                AskGlassGroup { EmptyView() }
            } content: {
                GeometryReader { proxy in
                    measured.contentHeight = proxy.size.height
                    return Color.red
                }
            }
            .environment(\.dynamicTypeSize, size)
            let renderer = ImageRenderer(content: screen)
            renderer.proposedSize = ProposedViewSize(width: 300, height: Self.conversation)
            _ = try #require(renderer.cgImage)
            #expect(measured.contentHeight == Self.conversation)
        }
    }
}

#endif
